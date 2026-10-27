import Foundation
import Combine
#if canImport(SessionDomain)
import SessionDomain
#endif

/// Puts the recordings received from the Watch into the folder the user picked once (usually iCloud Drive/Personal
/// Memory), where the Mac app reads them. The app keeps a bookmark to the folder; the originals stay on this iPhone.
@MainActor
final class RelayFolderSender: ObservableObject {
    @Published private(set) var folderName: String?
    @Published private(set) var status = "Macと共有するフォルダを選ぶと、届いた録音を自動で置きます。"
    @Published private(set) var sentCount = 0
    private static let key = "relayFolderBookmark"
    private static let sentKey = "relayFolderSent"
    private var sent: Set<String>

    init() {
        sent = Set(UserDefaults.standard.stringArray(forKey: Self.sentKey) ?? [])
        sentCount = sent.count
        folderName = (try? resolve())?.lastPathComponent
    }

    /// The folder from the file picker (security-scoped while the picker's grant lasts; kept as a bookmark).
    func choose(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.key)
            folderName = url.lastPathComponent
            sent = []; UserDefaults.standard.set([String](), forKey: Self.sentKey); sentCount = 0
            status = "「\(url.lastPathComponent)」に置きます。"
            sendPending()
        } catch { status = "このフォルダは使えません。\(error.localizedDescription)" }
    }

    /// Sends every received piece not sent to the current folder yet. Safe to call often.
    func sendPending() {
        guard let folder = try? resolve() else { return }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        do {
            let inbox = SessionChunkInbox(directory: try CaptureAudioInbox.defaultDirectory().appendingPathComponent("Sessions"))
            var added = 0, failed = 0
            for piece in try inbox.pieces() where !sent.contains(piece.chunk.chunkID.uuidString) {
                do {
                    _ = try RelayFolder.deposit(audio: piece.audio, chunk: piece.chunk, into: folder)
                    sent.insert(piece.chunk.chunkID.uuidString); added += 1
                } catch { failed += 1 }
            }
            UserDefaults.standard.set(Array(sent), forKey: Self.sentKey)
            sentCount = sent.count
            // Pieces the user deleted on the Mac (2026-10-27): delete this iPhone's audio, then clear the marks.
            let retired = try RelayFolder.retiredMarks(in: folder)
            let removed = retired.isEmpty ? 0 : try inbox.removeAudio(of: Set(retired))
            for id in retired { try RelayFolder.clearMark(id, in: folder) }
            if removed > 0 { status = "Macで削除された録音\(removed)件を、このiPhoneからも消しました。"; return }
            status = failed > 0 ? "\(failed)件を置けませんでした。次に開いたときにもう一度試します。"
                : added > 0 ? "\(added)件をフォルダに置きました(合計\(sentCount)件)。" : "送る録音はすべてフォルダにあります(\(sentCount)件)。"
        } catch { status = "録音を送れませんでした。\(error.localizedDescription)" }
    }

    private func resolve() throws -> URL {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.key) else { throw CocoaError(.fileNoSuchFile) }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.key)
        }
        return url
    }
}

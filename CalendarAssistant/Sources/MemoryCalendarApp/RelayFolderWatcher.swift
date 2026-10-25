import AppKit
import SwiftUI
import Combine
import SessionDomain

/// Reads recordings the iPhone put in the shared folder (usually iCloud Drive/Personal Memory) while this app is open:
/// pieces still only in iCloud are asked to download, downloaded pieces are verified and saved like a nearby delivery.
/// The folder is only read; the iPhone keeps its originals.
@MainActor
final class RelayFolderWatcher: ObservableObject {
    @Published private(set) var folder: URL?
    @Published private(set) var status = "iPhoneと共有するフォルダを選んでください。"
    private let receiver: NearbyChunkReceiver
    private var timer: AnyCancellable?
    private var failed: Set<String> = []
    private static let key = "relayFolderPath"

    static var iCloudDrive: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    }

    init(receiver: NearbyChunkReceiver) {
        self.receiver = receiver
        if let path = UserDefaults.standard.string(forKey: Self.key) {
            folder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            // The name the iPhone screen suggests: used without asking when it is already in iCloud Drive.
            let suggested = Self.iCloudDrive.appendingPathComponent("Personal Memory", isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: suggested.path, isDirectory: &isDirectory), isDirectory.boolValue {
                use(suggested)
            }
        }
        timer = Timer.publish(every: 20, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.check() }
        check()
    }

    func choose() {
        let panel = NSOpenPanel()
        // A recording inside the folder may be picked too (its folder is used): with folders only, the files inside
        // showed greyed out and Open stayed disabled, which looked broken.
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "このフォルダを使う"
        panel.message = "iPhoneで選んだのと同じフォルダ(例: iCloud Drive の Personal Memory)か、その中の録音を選んでください。"
        panel.directoryURL = folder ?? Self.iCloudDrive
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        use(isDirectory ? url : url.deletingLastPathComponent())
    }

    private func use(_ url: URL) {
        folder = url
        UserDefaults.standard.set(url.path, forKey: Self.key)
        failed = []
        check()
    }

    func check() {
        guard let folder else { return }
        do {
            let scan = try RelayFolder.scan(folder, imported: Set(receiver.savedChunks.map(\.chunkID)))
            for placeholder in scan.notDownloaded {
                // `.<id>.pmchunk.icloud` stands for `<id>.pmchunk`, which iCloud fetches on request.
                let name = String(placeholder.lastPathComponent.dropFirst().dropLast(".icloud".count))
                try? FileManager.default.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(name))
            }
            var imported = 0
            for file in scan.ready where !failed.contains(file.lastPathComponent) {
                do { try receiver.importBundle(file, named: file.lastPathComponent); imported += 1 }
                catch { failed.insert(file.lastPathComponent) }   // A broken piece is reported once, not retried every 20 s.
            }
            var parts = ["「\(folder.lastPathComponent)」を確認しました。"]
            if imported > 0 { parts.append("\(imported)件を取り込みました。") }
            if !scan.notDownloaded.isEmpty { parts.append("iCloudからダウンロード中: \(scan.notDownloaded.count)件。") }
            if !failed.isEmpty { parts.append("確かめられなかった録音: \(failed.count)件(取り込んでいません)。") }
            status = parts.joined(separator: " ")
        } catch {
            status = "フォルダを読めません。\(error.localizedDescription)"
        }
    }
}

struct RelayFolderRow: View {
    @ObservedObject var watcher: RelayFolderWatcher
    var body: some View {
        HStack {
            Label("共有フォルダ", systemImage: "icloud.and.arrow.down")
            Spacer()
            Text(watcher.folder?.lastPathComponent ?? "未設定").foregroundStyle(.secondary)
            Button(watcher.folder == nil ? "フォルダを選ぶ…" : "変更…") { watcher.choose() }
        }
        Text("iPhoneが置いた録音を20秒ごとに確認して取り込みます。" + watcher.status)
            .font(.caption).foregroundStyle(.secondary)
    }
}

import Foundation
import Combine
import CryptoKit
@preconcurrency import WatchConnectivity
#if canImport(SessionDomain)
import SessionDomain
#endif

@MainActor
final class WatchCaptureReceiver: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status = "Watchからの受信を待っています"
    @Published private(set) var receivedCount = 0

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        Task { await refreshInitialCount() }
    }

    private func refreshInitialCount() async {
        do {
            let dir = try CaptureAudioInbox.defaultDirectory()
            let inbox = CaptureAudioInbox(directory: dir)
            let chunks = SessionChunkInbox(directory: dir.appendingPathComponent("Sessions"))
            let count = try inbox.recordings().count + chunks.receiptCount()
            self.receivedCount = count
            self.status = "保持中の録音: \(count)件"
        } catch {
            self.status = "初期読み込み失敗: \(error.localizedDescription)"
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        do {
            let dir = try CaptureAudioInbox.defaultDirectory()
            let inbox = CaptureAudioInbox(directory: dir)
            let sessionInbox = SessionChunkInbox(directory: dir.appendingPathComponent("Sessions"))
            if let chunkData = file.metadata?["chunkJSON"] as? Data {
                let chunk = try JSONDecoder().decode(RecordingSession.Chunk.self, from: chunkData)
                _ = try sessionInbox.receive(fileURL: file.fileURL, chunk: chunk)
                // Saved and checked against the Watch's SHA-256: the Watch may now delete its copy (2026-10-27).
                session.transferUserInfo(["saved": [chunk.chunkID.uuidString: chunk.checksum]])
            } else {
                guard let idString = file.metadata?["captureID"] as? String,
                      let captureId = UUID(uuidString: idString) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let saved = try inbox.receive(fileURL: file.fileURL, id: captureId)
                let sum = SHA256.hash(data: try Data(contentsOf: saved, options: .mappedIfSafe))
                    .map { String(format: "%02x", $0) }.joined()
                session.transferUserInfo(["saved": [captureId.uuidString: sum]])
            }
            let count = try inbox.recordings().count + sessionInbox.receiptCount()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.receivedCount = count
                self.status = "受信完了 (合計 \(count)件)"
            }
        } catch {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.status = "受信失敗: \(error.localizedDescription)"
            }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let errorMessage = error?.localizedDescription ?? ""
        switch activationState {
        case .activated:
            // Pieces this iPhone already holds, so a Watch that never heard back can delete them without sending again.
            if let dir = try? CaptureAudioInbox.defaultDirectory(),
               let pieces = try? SessionChunkInbox(directory: dir.appendingPathComponent("Sessions")).pieces(), !pieces.isEmpty {
                session.transferUserInfo(["saved": Dictionary(pieces.map { ($0.chunk.chunkID.uuidString, $0.chunk.checksum) },
                                                              uniquingKeysWith: { first, _ in first })])
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.status = "Watchからの受信を待っています"
            }
        case .inactive, .notActivated:
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.status = errorMessage.isEmpty ? "Watch未接続" : errorMessage
            }
        default:
            break
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}

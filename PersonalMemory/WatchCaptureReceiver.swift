import Foundation
import Combine
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
            } else {
                guard let idString = file.metadata?["captureID"] as? String,
                      let captureId = UUID(uuidString: idString) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                _ = try inbox.receive(fileURL: file.fileURL, id: captureId)
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

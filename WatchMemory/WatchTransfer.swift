import Foundation
import Combine
@preconcurrency import WatchConnectivity

@MainActor
final class WatchTransfer: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status = "転送を準備しています"

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            status = "WatchConnectivityが利用できません"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendPending() {
#if targetEnvironment(simulator)
        status = "転送はペアリングした実機で確認できます。録音はWatchに残ります。"
#else
        guard WCSession.default.activationState == .activated else {
            status = "接続を待っています。録音は保持しています。"
            return
        }

        do {
            let dir = try WatchRecorder.directory()
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            
            var queuedCount = 0
            for url in files {
                guard url.pathExtension == "m4a", !url.lastPathComponent.hasSuffix(".pending.m4a") else { continue }
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                guard (attrs[.type] as? FileAttributeType) == .typeRegular else { continue }

                let uuidString = url.deletingPathExtension().lastPathComponent
                guard UUID(uuidString: uuidString) != nil else { continue }
                
                let alreadyQueued = WCSession.default.outstandingFileTransfers.contains { transfer in
                    if let meta = transfer.file.metadata, let id = meta["captureID"] as? String {
                        return id == uuidString
                    }
                    return false
                }

                guard !alreadyQueued else { continue }

                var metadata: [String: Any] = ["captureID": uuidString]
                let manifest = url.deletingPathExtension().appendingPathExtension("json")
                if FileManager.default.fileExists(atPath: manifest.path) {
                    let data = try Data(contentsOf: manifest)
                    let chunk = try JSONDecoder().decode(RecordingSession.Chunk.self, from: data)
                    guard chunk.chunkID.uuidString == uuidString else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    metadata["chunkJSON"] = data
                }
                WCSession.default.transferFile(url, metadata: metadata)
                queuedCount += 1
            }

            if queuedCount > 0 {
                status = "転送キューに追加しました。iPhoneでの保存をお待ちください。"
            } else {
                status = "新しく送る録音はありません。送信待ちの録音と原本は保持しています。"
            }
        } catch {
            status = "ファイルの読み込みに失敗しました: \(error.localizedDescription)"
        }
#endif
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let errorMessage = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let errorMessage {
                self.status = "接続エラー: \(errorMessage)"
            } else if activationState == .activated {
                self.status = "転送の準備ができました。"
                self.sendPending()
            } else {
                self.status = "接続が完了しませんでした。録音は保持しています。"
            }
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        let errorMessage = error?.localizedDescription ?? ""
        Task { @MainActor [weak self] in
            guard let self else { return }
            if errorMessage.isEmpty {
                self.status = "転送処理が終了しました。原本はWatchに残しています。"
            } else {
                self.status = "転送に失敗しました: \(errorMessage)。原本はWatchに残しています。"
            }
        }
    }
}

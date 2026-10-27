import Foundation
import Combine
import CryptoKit
@preconcurrency import WatchConnectivity

/// Sends finished pieces to the iPhone and deletes a piece from the Watch once the iPhone says it saved the same bytes
/// (2026-10-27). Until then the Watch keeps it. A delivered piece is not queued again for `resendAfter`; the earlier
/// version re-queued every piece it held after each new one, and a long day waited hours behind its own copies.
@MainActor
final class WatchTransfer: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status = "転送を準備しています"
    /// Changes whenever pieces are deleted, so the recordings list reloads.
    @Published private(set) var deletedCount = 0
    /// What the last send or confirmation means for the user (TransferReport), and when it happened.
    @Published private(set) var headline = ""
    @Published private(set) var detail = ""
    @Published private(set) var updatedAt: Date?
    private var lastFailure: String?
    private static let sentKey = "watchSentAt"
    private let resendAfter: TimeInterval = 6 * 3600

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            status = "WatchConnectivityが利用できません"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private var sentAt: [UUID: Date] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: Self.sentKey) as? [String: Date] ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, date in UUID(uuidString: key).map { ($0, date) } })
        }
        set {
            UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) }),
                                      forKey: Self.sentKey)
        }
    }

    func sendPending(pressedByUser: Bool = false) {
#if targetEnvironment(simulator)
        status = "転送はペアリングした実機で確認できます。録音はWatchに残ります。"
#else
        guard WCSession.default.activationState == .activated else {
            status = "接続を待っています。録音は保持しています。"
            return
        }
        do {
            let pieces = try finishedPieces()
            let outstanding = Set(WCSession.default.outstandingFileTransfers.compactMap {
                ($0.file.metadata?["captureID"] as? String).flatMap(UUID.init(uuidString:))
            })
            let send = WatchDelivery.toSend(local: pieces.map(\.id), outstanding: outstanding, sentAt: sentAt,
                                            now: Date(), resendAfter: resendAfter)
            let byID = Dictionary(uniqueKeysWithValues: pieces.map { ($0.id, $0.url) })
            for id in send {
                guard let url = byID[id] else { continue }
                var metadata: [String: Any] = ["captureID": id.uuidString]
                let manifest = url.deletingPathExtension().appendingPathExtension("json")
                if FileManager.default.fileExists(atPath: manifest.path) {
                    let data = try Data(contentsOf: manifest)
                    let chunk = try JSONDecoder().decode(RecordingSession.Chunk.self, from: data)
                    guard chunk.chunkID == id else { throw CocoaError(.fileReadCorruptFile) }
                    metadata["chunkJSON"] = data
                }
                WCSession.default.transferFile(url, metadata: metadata)
            }
            report(onWatch: pieces.count, queuedNow: send.count, inFlight: outstanding.count, pressedByUser: pressedByUser)
        } catch {
            status = "ファイルの読み込みに失敗しました: \(error.localizedDescription)"
        }
#endif
    }

    private var retry: Task<Void, Never>?

    /// A failed transfer used to wait for the next new piece or a manual resend (2026-10-27: the last six pieces of the
    /// day stayed on the Watch). Try again after a minute; several failures share one retry.
    private func scheduleRetry() {
        guard retry == nil else { return }
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled else { return }
            self.retry = nil
            self.sendPending()
        }
    }

    private func report(onWatch: Int, queuedNow: Int, inFlight: Int, pressedByUser: Bool) {
        let snapshot = TransferSnapshot(onWatch: onWatch, queuedNow: queuedNow, inFlight: inFlight, lastFailure: lastFailure,
                                        deletedSinceOpen: deletedCount, pressedByUser: pressedByUser)
        headline = TransferReport.headline(snapshot)
        detail = TransferReport.detail(snapshot)
        updatedAt = Date()
    }

    /// After a transfer finished or the iPhone confirmed: the same report with the current counts.
    private func refreshReport() {
        let inFlight = WCSession.isSupported() ? WCSession.default.outstandingFileTransfers.count : 0
        report(onWatch: (try? finishedPieces().count) ?? 0, queuedNow: 0, inFlight: inFlight, pressedByUser: false)
    }

    /// Finished pieces on the Watch, oldest name first (pieces still being written end in `.pending.m4a`).
    private func finishedPieces() throws -> [(id: UUID, url: URL)] {
        let dir = try WatchRecorder.directory()
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).compactMap { url in
            guard url.pathExtension == "m4a", !url.lastPathComponent.hasSuffix(".pending.m4a"),
                  (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular,
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
            return (id, url)
        }.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    /// The iPhone's acknowledgement: `["saved": [chunkID: sha256]]`.
    private func deleteSaved(_ acknowledged: [String: String]) {
        do {
            let dir = try WatchRecorder.directory()
            var local: [UUID: String] = [:]
            for key in acknowledged.keys {
                guard let id = UUID(uuidString: key) else { continue }
                let audio = dir.appendingPathComponent(id.uuidString + ".m4a")
                guard FileManager.default.fileExists(atPath: audio.path) else { continue }
                let manifest = dir.appendingPathComponent(id.uuidString + ".json")
                if let data = try? Data(contentsOf: manifest),
                   let chunk = try? JSONDecoder().decode(RecordingSession.Chunk.self, from: data) {
                    local[id] = chunk.checksum
                } else if let sum = try? Self.checksum(audio) {
                    local[id] = sum   // Single recordings from before pieces have no manifest.
                }
            }
            var seen = Set<UUID>()
            let ids = WatchDelivery.deletable(acknowledged: acknowledged, local: local).filter { seen.insert($0).inserted }
            guard !ids.isEmpty else { return }
            var sent = sentAt
            for id in ids {
                // Audio first: a manifest without audio is ignored, audio without a manifest would be sent again.
                try FileManager.default.removeItem(at: dir.appendingPathComponent(id.uuidString + ".m4a"))
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(id.uuidString + ".json"))
                sent[id] = nil
            }
            sentAt = sent
            deletedCount += ids.count
            refreshReport()
        } catch {
            status = "Watchの録音を整理できませんでした: \(error.localizedDescription)"
        }
    }

    private static func checksum(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
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
        let errorMessage = error?.localizedDescription
        let id = (fileTransfer.file.metadata?["captureID"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let errorMessage {
                self.lastFailure = errorMessage
                self.refreshReport()
                self.scheduleRetry()
            } else if let id {
                var sent = self.sentAt
                sent[id] = Date()
                self.sentAt = sent
                self.lastFailure = nil
                self.refreshReport()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let saved = userInfo["saved"] as? [String: String] else { return }
        Task { @MainActor [weak self] in self?.deleteSaved(saved) }
    }
}

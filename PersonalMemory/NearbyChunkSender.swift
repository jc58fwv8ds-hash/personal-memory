import Foundation
import Combine
@preconcurrency import MultipeerConnectivity

@MainActor
final class NearbyChunkSender: NSObject, ObservableObject {
    enum Phase: String {
        case searching, ready, connecting, connected, sending, awaitingReceipt, saved, problem

        var title: String {
            switch self {
            case .searching: "Macを探しています"
            case .ready: "Macが見つかりました"
            case .connecting: "Macへ接続中"
            case .connected: "Macと接続済み"
            case .sending: "録音を送信中"
            case .awaitingReceipt: "Macに保存できたか確認中"
            case .saved: "Macに保存済み"
            case .problem: "確認が必要です"
            }
        }

        var symbol: String {
            switch self {
            case .searching: "magnifyingglass"
            case .ready, .connecting, .connected: "laptopcomputer.and.iphone"
            case .sending, .awaitingReceipt: "arrow.up.circle"
            case .saved: "checkmark.circle.fill"
            case .problem: "exclamationmark.circle"
            }
        }
    }
    private struct PeerReference: @unchecked Sendable { let peer: MCPeerID }
    @Published var pairingCode = ""
    @Published private(set) var status = "Macを探しています"
    @Published private(set) var phase: Phase = .searching
    @Published private(set) var macName: String?
    private let peer = MCPeerID(displayName: "Personal Memory iPhone")
    private var browser: MCNearbyServiceBrowser?
    private var session: MCSession?
    private var discovered: MCPeerID?
    private var transferInProgress = false
    private var awaitingAck = Set<UUID>()

    override init() {
        super.init()
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: "pmemory-sync")
        browser.delegate = self
        self.browser = browser
        browser.startBrowsingForPeers()
    }

    private func publish(_ phase: Phase, _ message: String) {
        self.phase = phase
        status = message
    }

    func connect() {
        guard let discovered, let session, pairingCode.count == 6,
              pairingCode.allSatisfy(\.isNumber) else {
            publish(.ready, "Macの6桁の番号を入力してください。")
            return
        }
        browser?.invitePeer(discovered, to: session, withContext: Data(pairingCode.utf8), timeout: 20)
        publish(.connecting, "Macへ接続しています")
    }

    func sendPending() {
        guard !transferInProgress, let session,
              let mac = session.connectedPeers.first else {
            if session?.connectedPeers.isEmpty != false { publish(.searching, "Macとの接続を待っています") }
            return
        }
        do {
            let inbox = try CaptureAudioInbox.defaultDirectory().appendingPathComponent("Sessions")
            let manager = FileManager.default
            guard manager.fileExists(atPath: inbox.path) else { publish(.connected, "送信待ちの録音はありません"); return }
            let sessions = try manager.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
            for folder in sessions where UUID(uuidString: folder.lastPathComponent) != nil {
                let files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                for manifest in files where manifest.pathExtension == "json" {
                    guard let id = UUID(uuidString: manifest.deletingPathExtension().lastPathComponent),
                          !awaitingAck.contains(id) else { continue }
                    let audio = folder.appendingPathComponent(id.uuidString + ".m4a")
                    let ack = folder.appendingPathComponent(id.uuidString + ".mac-ack")
                    guard manager.fileExists(atPath: audio.path), !manager.fileExists(atPath: ack.path) else { continue }
                    let chunk = try JSONDecoder().decode(RecordingSession.Chunk.self,
                        from: Data(contentsOf: manifest))
                    guard chunk.chunkID == id else { throw CocoaError(.fileReadCorruptFile) }
                    let bundle = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pmchunk")
                    try ChunkTransferBundle.pack(audio: audio, chunk: chunk, destination: bundle)
                    transferInProgress = true
                    publish(.sending, "録音をMacへ送っています")
                    let target = PeerReference(peer: mac)
                    session.sendResource(at: bundle, withName: id.uuidString + ".pmchunk", toPeer: mac,
                                         withCompletionHandler: Self.resourceCompletion(
                                            owner: self, bundle: bundle, ack: ack, id: id, target: target))
                    return
                }
            }
            if phase != .saved { publish(.connected, "送信待ちの録音はありません") }
        } catch { publish(.problem, "送信準備に失敗しました: \(error.localizedDescription)") }
    }

    // MultipeerConnectivity calls this closure from its own queue. Build it in a
    // nonisolated context, then explicitly hop to MainActor before changing UI state.
    private nonisolated static func resourceCompletion(
        owner: NearbyChunkSender, bundle: URL, ack: URL, id: UUID, target: PeerReference
    ) -> (Error?) -> Void {
        { [weak owner] error in
            Task { @MainActor [weak owner] in
                try? FileManager.default.removeItem(at: bundle)
                guard let owner else { return }
                owner.transferInProgress = false
                if let error {
                    owner.publish(.problem, "送信失敗: \(error.localizedDescription)。再試行は画面のボタンから行えます。")
                    return
                }
                if !FileManager.default.fileExists(atPath: ack.path) {
                    owner.awaitingAck.insert(id)
                    owner.publish(.awaitingReceipt, "Macでの保存確認を待っています")
                }
                if owner.session?.connectedPeers.contains(target.peer) == true { owner.sendPending() }
            }
        }
    }
}

extension NearbyChunkSender: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        let candidate = PeerReference(peer: peerID)
        Task { @MainActor [weak self] in
            self?.discovered = candidate.peer
            self?.macName = candidate.peer.displayName
            self?.publish(.ready, "Macが見つかりました")
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.discovered = nil; self?.macName = nil
            self?.publish(.searching, "Macを探しています")
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        Task { @MainActor [weak self] in self?.publish(.problem, "Macを探せません: \(error.localizedDescription)") }
    }
}

extension NearbyChunkSender: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if state == .connected { self.publish(.connected, "Macと接続しました"); self.sendPending() }
            else if state == .notConnected {
                self.awaitingAck.removeAll()
                self.publish(.searching, "Macとの接続が切れました")
            }
        }
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            guard let self, let text = String(data: data, encoding: .utf8) else { return }
            let parts = text.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "ACK", let id = UUID(uuidString: String(parts[1])) else { return }
            do {
                let root = try CaptureAudioInbox.defaultDirectory().appendingPathComponent("Sessions")
                let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                for folder in folders {
                    let manifest = folder.appendingPathComponent(id.uuidString + ".json")
                    guard FileManager.default.fileExists(atPath: manifest.path) else { continue }
                    let chunk = try JSONDecoder().decode(RecordingSession.Chunk.self,
                        from: Data(contentsOf: manifest))
                    guard chunk.chunkID == id, chunk.checksum == parts[2] else { return }
                    try Data().write(to: folder.appendingPathComponent(id.uuidString + ".mac-ack"), options: .atomic)
                    self.awaitingAck.remove(id)
                    self.publish(.saved, "Macで保存を確認しました。iPhoneの原本も保持しています。")
                    self.sendPending()
                    return
                }
            } catch { self.publish(.problem, "Macの保存確認を記録できませんでした") }
        }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName name: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName name: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName name: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}
    nonisolated func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID,
                             certificateHandler: @escaping (Bool) -> Void) { certificateHandler(true) }
}

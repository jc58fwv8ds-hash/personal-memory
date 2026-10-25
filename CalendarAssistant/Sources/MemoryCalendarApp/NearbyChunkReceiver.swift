import Foundation
import Combine
@preconcurrency import MultipeerConnectivity
import CalendarDomain
import SessionDomain

@MainActor
final class NearbyChunkReceiver: NSObject, ObservableObject {
    struct ReceivedChunk: Equatable { let audioURL: URL; let startedAt: Date }
    private struct InvitationReply: @unchecked Sendable {
        let call: (Bool, MCSession?) -> Void
    }
    private struct PeerReference: @unchecked Sendable { let peer: MCPeerID }
    @Published private(set) var status = "iPhoneを待っています"
    @Published private(set) var receivedCount = 0
    @Published private(set) var latestChunk: ReceivedChunk?
    @Published private(set) var savedChunks: [SessionChunkReceipt] = []
    let pairingCode = String(format: "%06d", Int.random(in: 100_000...999_999))
    private let peer = MCPeerID(displayName: Host.current().localizedName ?? "Personal Memory Mac")
    private var advertiser: MCNearbyServiceAdvertiser?
    private var session: MCSession?
    private var failedInvitations = 0
    private let workspace: SessionChunkWorkspace

    init(root: URL) {
        workspace = SessionChunkWorkspace(root: root)
        super.init()
        do { savedChunks = try workspace.receipts(); receivedCount = savedChunks.count }
        catch { status = "保存済み録音の一覧を読めません: \(error.localizedDescription)" }
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: "pmemory-sync")
        advertiser.delegate = self
        self.advertiser = advertiser
        advertiser.startAdvertisingPeer()
    }

}

extension NearbyChunkReceiver: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let reply = InvitationReply(call: invitationHandler)
        Task { @MainActor [weak self] in
            guard let self else { reply.call(false, nil); return }
            let valid = self.failedInvitations < 3 && context == Data(self.pairingCode.utf8)
            if !valid {
                self.failedInvitations += 1
                self.status = "接続コードが一致しません。"
                if self.failedInvitations >= 3 { self.advertiser?.stopAdvertisingPeer() }
            }
            reply.call(valid, valid ? self.session : nil)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        Task { @MainActor [weak self] in self?.status = "近くのiPhoneを探せません: \(error.localizedDescription)" }
    }
}

extension NearbyChunkReceiver: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            self?.status = state == .connected ? "iPhoneと接続しました" : "iPhoneを待っています"
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {
        let sender = PeerReference(peer: peerID)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard error == nil, let localURL else { throw CocoaError(.fileReadCorruptFile) }
                let chunk = try self.importBundle(localURL, named: resourceName)
                self.status = "録音を検証してMacに保存しました（\(self.receivedCount)件）"
                let acknowledgement = Data(("ACK|" + chunk.chunkID.uuidString + "|" + chunk.checksum).utf8)
                try self.session?.send(acknowledgement, toPeers: [sender.peer], with: .reliable)
            } catch {
                self.status = "録音を受信できませんでした: \(error.localizedDescription)"
            }
        }
    }

    /// Verifies and saves one `<chunkID>.pmchunk` bundle, from the nearby iPhone or the shared folder (RelayFolderWatcher).
    @discardableResult
    func importBundle(_ bundle: URL, named name: String) throws -> RecordingSession.Chunk {
        guard name.hasSuffix(".pmchunk"), UUID(uuidString: String(name.dropLast(".pmchunk".count))) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let chunk = try ChunkTransferBundle.unpack(bundle: bundle, audioDestination: temporary)
        guard UUID(uuidString: String(name.dropLast(".pmchunk".count))) == chunk.chunkID else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let receipt = try workspace.importChunk(audio: temporary, metadata: chunk)
        latestChunk = ReceivedChunk(audioURL: audioURL(for: receipt), startedAt: chunk.start)
        savedChunks = try workspace.receipts()
        receivedCount = savedChunks.count
        return chunk
    }

    func audioURL(for receipt: SessionChunkReceipt) -> URL {
        workspace.root.appendingPathComponent("Audio/\(receipt.recordingHash).m4a")
    }

    nonisolated func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?,
                             fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true) // The invitation is admitted only after the displayed code matches.
    }
}

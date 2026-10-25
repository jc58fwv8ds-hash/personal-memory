import Foundation
import CryptoKit
import SessionDomain

public struct SessionChunkReceipt: Codable, Equatable, Identifiable, Sendable {
    public let sessionID: UUID
    public let chunkID: UUID
    public let sequence: Int
    public let start: Date
    public let end: Date
    public let recordingHash: String
    public var id: UUID { chunkID }
}

/// Mac's durable, verified import boundary for a transferred chunk.
public struct SessionChunkWorkspace: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }

    public func receipts() throws -> [SessionChunkReceipt] {
        let folder = root.appendingPathComponent("Receipts", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return try files.filter { $0.pathExtension == "json" }.map { url in
            let receipt = try JSONDecoder().decode(SessionChunkReceipt.self,
                from: Data(contentsOf: url))
            guard url.deletingPathExtension().lastPathComponent == receipt.chunkID.uuidString,
                  FileManager.default.fileExists(atPath: root.appendingPathComponent("Audio/\(receipt.recordingHash).m4a").path)
            else { throw RecordingWorkspace.WorkspaceError.corrupt }
            return receipt
        }.sorted { $0.start < $1.start }
    }

    public func importChunk(audio: URL, metadata: RecordingSession.Chunk) throws -> SessionChunkReceipt {
        guard metadata.sequence > 0, metadata.end >= metadata.start,
              metadata.duration.isFinite, metadata.duration > 0,
              metadata.duration <= metadata.end.timeIntervalSince(metadata.start) + 1,
              metadata.localState == "committed", metadata.checksum.count == 64,
              metadata.checksum.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw RecordingWorkspace.WorkspaceError.corrupt
        }
        let hash = try checksum(audio)
        guard hash == metadata.checksum else { throw RecordingWorkspace.WorkspaceError.corrupt }
        let recording = RecordingWorkspace(root: root.appendingPathComponent("Audio"))
        let document = try recording.importRecording(audio)
        guard document.recordingHash == hash else { throw RecordingWorkspace.WorkspaceError.corrupt }
        let receipt = SessionChunkReceipt(sessionID: metadata.sessionID, chunkID: metadata.chunkID,
            sequence: metadata.sequence, start: metadata.start, end: metadata.end, recordingHash: hash)
        let receipts = root.appendingPathComponent("Receipts", isDirectory: true)
        try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: receipts.path)
        let destination = receipts.appendingPathComponent(metadata.chunkID.uuidString + ".json")
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try JSONDecoder().decode(SessionChunkReceipt.self,
                from: Data(contentsOf: destination)) == receipt else {
                throw RecordingWorkspace.WorkspaceError.corrupt
            }
        } else {
            try JSONEncoder().encode(receipt).write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
        return receipt
    }

    private func checksum(_ url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw RecordingWorkspace.WorkspaceError.invalidAudio
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            let bytes = try handle.read(upToCount: 1_048_576) ?? Data()
            if bytes.isEmpty { break }
            hash.update(data: bytes)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

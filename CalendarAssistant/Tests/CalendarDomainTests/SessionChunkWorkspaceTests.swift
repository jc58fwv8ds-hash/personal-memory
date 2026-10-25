import Foundation
import CryptoKit
import Testing
import SessionDomain
@testable import CalendarDomain

struct SessionChunkWorkspaceTests {
    @Test func verifiedChunkIsImportedOnceWithProvenance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audio = root.appendingPathComponent("source.m4a")
        let data = Data([1, 2, 3])
        try data.write(to: audio)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let start = Date(timeIntervalSince1970: 1000)
        var session = RecordingSession(start: start)
        try session.finalizeCommittedChunk(id: UUID(), end: start.addingTimeInterval(10),
            duration: 10, checksum: hash, boundary: .rollover)
        let chunk = try #require(session.chunks.first)
        let workspace = SessionChunkWorkspace(root: root.appendingPathComponent("workspace"))
        let first = try workspace.importChunk(audio: audio, metadata: chunk)
        #expect(first.sessionID == session.sessionID)
        #expect(first.sequence == 1)
        #expect(try workspace.importChunk(audio: audio, metadata: chunk) == first)
        #expect(try SessionChunkWorkspace(root: workspace.root).receipts() == [first])
        try Data([4]).write(to: audio)
        #expect(throws: (any Error).self) { try workspace.importChunk(audio: audio, metadata: chunk) }
        #expect(try JSONDecoder().decode(SessionChunkReceipt.self,
            from: Data(contentsOf: workspace.root.appendingPathComponent("Receipts/\(chunk.chunkID.uuidString).json"))) == first)
    }
}

import Foundation
import CryptoKit
import Testing
@testable import SessionDomain

struct ChunkTransferBundleTests {
    @Test func roundTripRejectsCorruptAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.m4a")
        let payload = Data([1, 2, 3, 4])
        try payload.write(to: source)
        let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let start = Date(timeIntervalSince1970: 1000)
        var session = RecordingSession(start: start)
        try session.finalizeCommittedChunk(id: UUID(), end: start.addingTimeInterval(10),
            duration: 10, checksum: hash, boundary: .stop)
        let chunk = try #require(session.chunks.first)
        let bundle = root.appendingPathComponent("transfer.pmchunk")
        try ChunkTransferBundle.pack(audio: source, chunk: chunk, destination: bundle)
        let received = root.appendingPathComponent("received.m4a")
        #expect(try ChunkTransferBundle.unpack(bundle: bundle, audioDestination: received) == chunk)
        #expect(try Data(contentsOf: received) == payload)
        var corrupt = try Data(contentsOf: bundle)
        corrupt[corrupt.count - 1] = 9
        try corrupt.write(to: bundle)
        let rejected = root.appendingPathComponent("rejected.m4a")
        #expect(throws: ChunkTransferBundle.Failure.self) {
            try ChunkTransferBundle.unpack(bundle: bundle, audioDestination: rejected)
        }
        #expect(!FileManager.default.fileExists(atPath: rejected.path))
    }
}

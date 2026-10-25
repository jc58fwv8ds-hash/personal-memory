import CryptoKit
import Foundation
import Testing
@testable import PersonalMemory
@testable import SessionDomain

@Test func receivedPiecesAreListedOldestFirstWithTheirMetadata() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-\(UUID().uuidString)")
    let inbox = SessionChunkInbox(directory: root)
    #expect(try inbox.pieces().isEmpty)
    let session = UUID()
    var chunks: [RecordingSession.Chunk] = []
    for (index, offset) in [600.0, 0.0].enumerated() {
        let data = Data("piece\(index)".utf8)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        try data.write(to: source)
        let start = Date(timeIntervalSince1970: 1_800_000_000 + offset)
        let chunk = RecordingSession.Chunk(sessionID: session, chunkID: UUID(), sequence: index + 1, start: start,
            end: start.addingTimeInterval(5), duration: 5,
            checksum: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            localState: "committed", transferState: "pending", boundary: .rollover)
        _ = try inbox.receive(fileURL: source, chunk: chunk)
        chunks.append(chunk)
    }
    // A metadata file without its audio is not a piece.
    try JSONEncoder().encode(chunks[0]).write(to: root.appendingPathComponent("\(session.uuidString)/\(UUID().uuidString).json"))
    let pieces = try inbox.pieces()
    #expect(pieces.map(\.chunk) == [chunks[1], chunks[0]])
    #expect(pieces.allSatisfy { FileManager.default.fileExists(atPath: $0.audio.path) })
}

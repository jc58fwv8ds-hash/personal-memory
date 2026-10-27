// Local Factory 課題 pm-relay-03 の見える試験と隠し試験(HarnessTasks/pm-relay-03)。
import Foundation
import CryptoKit
import Testing
import SessionDomain
@testable import PersonalMemory
/// An inbox holding one received piece per byte string, all in one recording session.
fileprivate func inbox(_ contents: [[UInt8]]) throws -> (SessionChunkInbox, URL, [RecordingSession.Chunk]) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let inbox = SessionChunkInbox(directory: root.appendingPathComponent("Sessions"))
    var session = RecordingSession(start: Date(timeIntervalSince1970: 1_800_000_000))
    for (index, bytes) in contents.enumerated() {
        let source = root.appendingPathComponent("source\(index).m4a")
        try Data(bytes).write(to: source)
        let hash = SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
        try session.finalizeCommittedChunk(id: UUID(), end: Date(timeIntervalSince1970: 1_800_000_000 + Double(index + 1) * 600),
                                           duration: 600, checksum: hash, boundary: .rollover)
        _ = try inbox.receive(fileURL: source, chunk: session.chunks[index])
    }
    return (inbox, root.appendingPathComponent("Sessions/\(session.sessionID.uuidString)"), session.chunks)
}

@Test func removedAudioIsGoneAndTheRecordStays() throws {
    let (inbox, folder, chunks) = try inbox([[1], [2]])
    #expect(try inbox.removeAudio(of: [chunks[0].chunkID]) == 1)
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(chunks[0].chunkID.uuidString + ".m4a").path))
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(chunks[0].chunkID.uuidString + ".json").path))
    #expect(try inbox.pieces().map(\.chunk.chunkID) == [chunks[1].chunkID])
}

@Test func unknownPiecesRemoveNothing() throws {
    let (inbox, _, _) = try inbox([[1]])
    #expect(try inbox.removeAudio(of: [UUID()]) == 0)
    #expect(try inbox.receiptCount() == 1)
}

@Test func holdoutRemovingTwiceCountsOnce() throws {
    let (inbox, _, chunks) = try inbox([[1]])
    #expect(try inbox.removeAudio(of: [chunks[0].chunkID]) == 1)
    #expect(try inbox.removeAudio(of: [chunks[0].chunkID]) == 0)
}

@Test func holdoutSeveralPiecesAndOthersStay() throws {
    let (inbox, _, chunks) = try inbox([[1], [2], [3]])
    #expect(try inbox.removeAudio(of: [chunks[0].chunkID, chunks[2].chunkID]) == 2)
    #expect(try inbox.receiptCount() == 1)
    #expect(try inbox.pieces().map(\.chunk.chunkID) == [chunks[1].chunkID])
}

@Test func holdoutAnEmptyOrMissingInboxIsFine() throws {
    let missing = SessionChunkInbox(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    #expect(try missing.removeAudio(of: [UUID()]) == 0)
    let (inbox, _, _) = try inbox([[1]])
    #expect(try inbox.removeAudio(of: []) == 0)
}

@Test func holdoutAudioWithoutItsRecordIsNotTouched() throws {
    let (inbox, folder, _) = try inbox([[1]])
    let stray = UUID()
    try Data([9]).write(to: folder.appendingPathComponent(stray.uuidString + ".m4a"))
    #expect(try inbox.removeAudio(of: [stray]) == 0)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(stray.uuidString + ".m4a").path))
}

@Test func holdoutPiecesInDifferentSessionsAreFound() throws {
    let (first, firstFolder, a) = try inbox([[1]])
    // A second session in the same inbox.
    let root = firstFolder.deletingLastPathComponent()
    var session = RecordingSession(start: Date(timeIntervalSince1970: 1_900_000_000))
    let source = root.deletingLastPathComponent().appendingPathComponent("other.m4a")
    try Data([5]).write(to: source)
    try session.finalizeCommittedChunk(id: UUID(), end: Date(timeIntervalSince1970: 1_900_000_600), duration: 600,
        checksum: SHA256.hash(data: Data([5])).map { String(format: "%02x", $0) }.joined(), boundary: .rollover)
    _ = try first.receive(fileURL: source, chunk: session.chunks[0])
    #expect(try first.removeAudio(of: [a[0].chunkID, session.chunks[0].chunkID]) == 2)
    #expect(try first.receiptCount() == 0)
}

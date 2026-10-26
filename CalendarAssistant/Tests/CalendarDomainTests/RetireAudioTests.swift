// Local Factory 課題 pm-day-08 の見える試験と隠し試験(HarnessTasks/pm-day-08)。
import Foundation
import CryptoKit
import Testing
import SessionDomain
@testable import CalendarDomain
/// A workspace with one imported piece per byte string; returns the workspace and the receipts in order.
fileprivate func workspace(_ contents: [[UInt8]]) throws -> (SessionChunkWorkspace, [SessionChunkReceipt]) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let workspace = SessionChunkWorkspace(root: root.appendingPathComponent("workspace"))
    var session = RecordingSession(start: Date(timeIntervalSince1970: 1_800_000_000))
    var receipts: [SessionChunkReceipt] = []
    for (index, bytes) in contents.enumerated() {
        let audio = root.appendingPathComponent("source\(index).m4a")
        try Data(bytes).write(to: audio)
        let hash = SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
        let end = Date(timeIntervalSince1970: 1_800_000_000 + Double(index + 1) * 600)
        try session.finalizeCommittedChunk(id: UUID(), end: end, duration: 600, checksum: hash, boundary: .rollover)
        receipts.append(try workspace.importChunk(audio: audio, metadata: session.chunks[index]))
    }
    return (workspace, receipts)
}

fileprivate func audio(_ workspace: SessionChunkWorkspace, _ receipt: SessionChunkReceipt) -> URL {
    workspace.root.appendingPathComponent("Audio/\(receipt.recordingHash).m4a")
}

@Test func retiredAudioGoesToTheTrashAndTheReceiptStays() throws {
    let (workspace, receipts) = try workspace([[1], [2]])
    var trashed: [URL] = []
    let count = try workspace.retireAudio(of: [receipts[0].chunkID]) { url in
        trashed.append(url); try FileManager.default.removeItem(at: url)
    }
    #expect(count == 1)
    #expect(trashed == [audio(workspace, receipts[0])])
    #expect(try workspace.receipts() == receipts)
    #expect(workspace.isRetired(receipts[0].chunkID))
    #expect(!workspace.isRetired(receipts[1].chunkID))
    #expect(FileManager.default.fileExists(atPath: audio(workspace, receipts[1]).path))
}

@Test func aMissingAudioThatWasNotRetiredIsStillCorrupt() throws {
    let (workspace, receipts) = try workspace([[1]])
    try FileManager.default.removeItem(at: audio(workspace, receipts[0]))
    #expect(throws: (any Error).self) { try workspace.receipts() }
}

@Test func holdoutAudioSharedWithAKeptPieceIsNotTrashed() throws {
    let (workspace, receipts) = try workspace([[7], [7], [8]])
    var trashed: [URL] = []
    let count = try workspace.retireAudio(of: [receipts[0].chunkID, receipts[2].chunkID]) { url in
        trashed.append(url); try FileManager.default.removeItem(at: url)
    }
    #expect(count == 1)
    #expect(trashed == [audio(workspace, receipts[2])])
    #expect(FileManager.default.fileExists(atPath: audio(workspace, receipts[0]).path))
    #expect(try workspace.receipts() == receipts)
}

@Test func holdoutRetiringTwiceOrUnknownIDsTrashesNothingMore() throws {
    let (workspace, receipts) = try workspace([[1]])
    try workspace.retireAudio(of: [receipts[0].chunkID]) { try FileManager.default.removeItem(at: $0) }
    var calls = 0
    #expect(try workspace.retireAudio(of: [receipts[0].chunkID, UUID()]) { _ in calls += 1 } == 0)
    #expect(calls == 0)
    #expect(!workspace.isRetired(UUID()))
}

@Test func holdoutAFailedTrashLeavesTheAudioListedAndUsable() throws {
    let (workspace, receipts) = try workspace([[1]])
    struct NoTrash: Error {}
    #expect(throws: NoTrash.self) { try workspace.retireAudio(of: [receipts[0].chunkID]) { _ in throw NoTrash() } }
    #expect(FileManager.default.fileExists(atPath: audio(workspace, receipts[0]).path))
    #expect(try workspace.receipts() == receipts)
}

@Test func holdoutReimportingARetiredPieceKeepsItsAudioDeleted() throws {
    let (workspace, receipts) = try workspace([[1]])
    try workspace.retireAudio(of: [receipts[0].chunkID]) { try FileManager.default.removeItem(at: $0) }
    // The shared folder offers the same piece again.
    let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
    try Data([1]).write(to: source)
    var session = RecordingSession(id: receipts[0].sessionID, start: receipts[0].start)
    let hash = receipts[0].recordingHash
    try session.finalizeCommittedChunk(id: receipts[0].chunkID, end: receipts[0].end, duration: 600, checksum: hash, boundary: .rollover)
    #expect(try workspace.importChunk(audio: source, metadata: session.chunks[0]) == receipts[0])
    #expect(!FileManager.default.fileExists(atPath: audio(workspace, receipts[0]).path))
}

@Test func holdoutRetiredPiecesSurviveANewWorkspaceValue() throws {
    let (workspace, receipts) = try workspace([[1], [2]])
    try workspace.retireAudio(of: Set(receipts.map(\.chunkID))) { try FileManager.default.removeItem(at: $0) }
    let reopened = SessionChunkWorkspace(root: workspace.root)
    #expect(try reopened.receipts() == receipts)
    #expect(receipts.allSatisfy { reopened.isRetired($0.chunkID) })
}

/// Added after the run (2026-10-27): audio shared only by retired pieces must go too, now or when the last one is retired.
@Test func holdoutSharedAudioGoesWhenEveryPieceUsingItIsRetired() throws {
    let (together, pair) = try workspace([[5], [5]])
    #expect(try together.retireAudio(of: Set(pair.map(\.chunkID))) { try FileManager.default.removeItem(at: $0) } == 1)
    #expect(!FileManager.default.fileExists(atPath: audio(together, pair[0]).path))
    let (oneByOne, pieces) = try workspace([[6], [6]])
    #expect(try oneByOne.retireAudio(of: [pieces[0].chunkID]) { try FileManager.default.removeItem(at: $0) } == 0)
    #expect(try oneByOne.retireAudio(of: [pieces[1].chunkID]) { try FileManager.default.removeItem(at: $0) } == 1)
    #expect(!FileManager.default.fileExists(atPath: audio(oneByOne, pieces[0]).path))
}

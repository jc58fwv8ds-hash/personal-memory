import CryptoKit
import Foundation
import Testing
@testable import SessionDomain

private func temp(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
private func piece(_ bytes: String, in directory: URL) throws -> (URL, RecordingSession.Chunk) {
    let data = Data(bytes.utf8)
    let audio = directory.appendingPathComponent(UUID().uuidString + ".m4a")
    try data.write(to: audio)
    let sum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let chunk = RecordingSession.Chunk(sessionID: UUID(), chunkID: UUID(), sequence: 1, start: start,
        end: start.addingTimeInterval(10), duration: 10, checksum: sum, localState: "committed",
        transferState: "pending", boundary: .stop)
    return (audio, chunk)
}

@Test func aDepositedPieceIsReadyAndUnpacksToTheSameAudio() throws {
    let source = try temp("src"), folder = try temp("folder"), out = try temp("out")
    let (audio, chunk) = try piece("音声のかわり", in: source)
    let file = try RelayFolder.deposit(audio: audio, chunk: chunk, into: folder)
    #expect(file.lastPathComponent == chunk.chunkID.uuidString + ".pmchunk")
    let scan = try RelayFolder.scan(folder, imported: [])
    #expect(scan.ready.map(\.lastPathComponent) == [file.lastPathComponent])
    #expect(scan.notDownloaded.isEmpty)
    let back = try ChunkTransferBundle.unpack(bundle: scan.ready[0], audioDestination: out.appendingPathComponent("a.m4a"))
    #expect(back == chunk)
    #expect(try Data(contentsOf: out.appendingPathComponent("a.m4a")) == Data("音声のかわり".utf8))
}

@Test func importedPiecesAreNotReadyAgain() throws {
    let source = try temp("src"), folder = try temp("folder")
    let (audio, chunk) = try piece("x", in: source)
    _ = try RelayFolder.deposit(audio: audio, chunk: chunk, into: folder)
    #expect(try RelayFolder.scan(folder, imported: [chunk.chunkID]).ready.isEmpty)
}

@Test func aPieceStillInTheCloudIsReportedAsNotDownloaded() throws {
    let folder = try temp("folder")
    let id = UUID()
    try Data().write(to: folder.appendingPathComponent(".\(id.uuidString).pmchunk.icloud"))
    let scan = try RelayFolder.scan(folder, imported: [])
    #expect(scan.ready.isEmpty)
    #expect(scan.notDownloaded.map(\.lastPathComponent) == [".\(id.uuidString).pmchunk.icloud"])
}

@Test func depositingTheSamePieceTwiceKeepsTheFirstFile() throws {
    let source = try temp("src"), folder = try temp("folder")
    let (audio, chunk) = try piece("一度だけ", in: source)
    let first = try RelayFolder.deposit(audio: audio, chunk: chunk, into: folder)
    let before = try FileManager.default.attributesOfItem(atPath: first.path)[.modificationDate] as? Date
    Thread.sleep(forTimeInterval: 1.1)
    let second = try RelayFolder.deposit(audio: audio, chunk: chunk, into: folder)
    #expect(second == first)
    #expect(try FileManager.default.attributesOfItem(atPath: first.path)[.modificationDate] as? Date == before)
}

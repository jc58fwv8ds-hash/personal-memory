import CryptoKit
import Foundation
import Testing
@testable import SessionDomain

private func temp(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("relay-h-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
private func piece(_ bytes: String, in directory: URL, checksum: String? = nil) throws -> (URL, RecordingSession.Chunk) {
    let data = Data(bytes.utf8)
    let audio = directory.appendingPathComponent(UUID().uuidString + ".m4a")
    try data.write(to: audio)
    let sum = checksum ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let chunk = RecordingSession.Chunk(sessionID: UUID(), chunkID: UUID(), sequence: 1, start: start,
        end: start.addingTimeInterval(10), duration: 10, checksum: sum, localState: "committed",
        transferState: "pending", boundary: .stop)
    return (audio, chunk)
}

@Test func holdoutAMissingFolderIsCreatedOnDepositAndScansEmpty() throws {
    let base = try temp("base")
    let folder = base.appendingPathComponent("iCloud/Personal Memory")
    #expect(try RelayFolder.scan(folder, imported: []) == RelayFolder.Scan())
    let (audio, chunk) = try piece("y", in: base)
    _ = try RelayFolder.deposit(audio: audio, chunk: chunk, into: folder)
    #expect(try RelayFolder.scan(folder, imported: []).ready.count == 1)
}

@Test func holdoutAWrongChecksumLeavesNothingInTheFolder() throws {
    let source = try temp("src"), folder = try temp("folder")
    let (audio, chunk) = try piece("z", in: source, checksum: String(repeating: "0", count: 64))
    #expect(throws: (any Error).self) { try RelayFolder.deposit(audio: audio, chunk: chunk, into: folder) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
}

@Test func holdoutOtherFilesAndHalfWrittenPiecesAreIgnored() throws {
    let folder = try temp("folder")
    let id = UUID()
    for name in ["\(id.uuidString).pmchunk.pending", "notes.pmchunk", "\(id.uuidString).m4a", ".DS_Store", "\(id.uuidString).PMCHUNK.txt"] {
        try Data("x".utf8).write(to: folder.appendingPathComponent(name))
    }
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("\(UUID().uuidString).pmchunk"), withIntermediateDirectories: true)
    #expect(try RelayFolder.scan(folder, imported: []) == RelayFolder.Scan())
}

@Test func holdoutAPlaceholderOfAnImportedOrDownloadedPieceIsNotReported() throws {
    let folder = try temp("folder")
    let imported = UUID(), downloaded = UUID()
    try Data().write(to: folder.appendingPathComponent(".\(imported.uuidString).pmchunk.icloud"))
    try Data().write(to: folder.appendingPathComponent(".\(downloaded.uuidString).pmchunk.icloud"))
    try Data("x".utf8).write(to: folder.appendingPathComponent("\(downloaded.uuidString).pmchunk"))
    let scan = try RelayFolder.scan(folder, imported: [imported])
    #expect(scan.notDownloaded.isEmpty)
    #expect(scan.ready.map(\.lastPathComponent) == ["\(downloaded.uuidString).pmchunk"])
}

@Test func holdoutResultsAreSortedByFileNameAndLowercaseNamesCount() throws {
    let folder = try temp("folder")
    let ids = (0..<3).map { _ in UUID() }
    for id in ids { try Data("x".utf8).write(to: folder.appendingPathComponent("\(id.uuidString.lowercased()).pmchunk")) }
    let names = try RelayFolder.scan(folder, imported: [ids[1]]).ready.map(\.lastPathComponent)
    #expect(names == [ids[0], ids[2]].map { "\($0.uuidString.lowercased()).pmchunk" }.sorted())
}

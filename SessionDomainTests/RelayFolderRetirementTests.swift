// Local Factory 課題 pm-relay-02 の見える試験と隠し試験(HarnessTasks/pm-relay-02)。
import Foundation
import Testing
@testable import SessionDomain
fileprivate func emptyFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

fileprivate func moveAway(_ url: URL) throws { try FileManager.default.removeItem(at: url) }

@Test func retiringTrashesTheSharedCopyAndLeavesAMark() throws {
    let folder = try emptyFolder()
    let id = UUID()
    let piece = folder.appendingPathComponent(id.uuidString + ".pmchunk")
    try Data([1]).write(to: piece)
    var trashed: [URL] = []
    #expect(try RelayFolder.retire([id], in: folder) { trashed.append($0); try moveAway($0) } == 1)
    #expect(trashed.map(\.lastPathComponent) == [piece.lastPathComponent])
    #expect(try RelayFolder.retiredMarks(in: folder) == [id])
}

@Test func aMarkIsClearedAfterTheIPhoneDeletedItsCopy() throws {
    let folder = try emptyFolder()
    let id = UUID()
    try RelayFolder.retire([id], in: folder, trash: moveAway)
    try RelayFolder.clearMark(id, in: folder)
    #expect(try RelayFolder.retiredMarks(in: folder).isEmpty)
}

@Test func aMissingFolderHasNoMarks() throws {
    #expect(try RelayFolder.retiredMarks(in: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)).isEmpty)
}

@Test func holdoutAPieceAlreadyGoneIsStillMarked() throws {
    let folder = try emptyFolder()
    let id = UUID()
    var calls = 0
    #expect(try RelayFolder.retire([id], in: folder) { _ in calls += 1 } == 0)
    #expect(calls == 0)
    #expect(try RelayFolder.retiredMarks(in: folder) == [id])
}

@Test func holdoutRepeatedIDsAreHandledOnce() throws {
    let folder = try emptyFolder()
    let id = UUID()
    try Data([1]).write(to: folder.appendingPathComponent(id.uuidString + ".pmchunk"))
    var calls = 0
    #expect(try RelayFolder.retire([id, id], in: folder) { calls += 1; try moveAway($0) } == 1)
    #expect(calls == 1)
}

@Test func holdoutTheMarkIsWrittenBeforeTheTrashSoAFailureStillReachesTheIPhone() throws {
    let folder = try emptyFolder()
    let id = UUID()
    try Data([1]).write(to: folder.appendingPathComponent(id.uuidString + ".pmchunk"))
    struct NoTrash: Error {}
    #expect(throws: NoTrash.self) { try RelayFolder.retire([id], in: folder) { _ in throw NoTrash() } }
    #expect(try RelayFolder.retiredMarks(in: folder) == [id])
}

@Test func holdoutOnlyRegularUUIDMarksCountAndTheyAreSorted() throws {
    let folder = try emptyFolder()
    let ids = (0..<3).map { _ in UUID() }
    try RelayFolder.retire(ids, in: folder, trash: moveAway)
    try Data().write(to: folder.appendingPathComponent("notes.retired"))
    try Data().write(to: folder.appendingPathComponent(UUID().uuidString + ".retired.tmp"))
    try FileManager.default.createDirectory(at: folder.appendingPathComponent(UUID().uuidString + ".retired"), withIntermediateDirectories: true)
    try Data().write(to: folder.appendingPathComponent(UUID().uuidString.lowercased() + ".pmchunk"))
    #expect(try RelayFolder.retiredMarks(in: folder) == ids.sorted { $0.uuidString < $1.uuidString })
}

@Test func holdoutLowercaseMarksAreRead() throws {
    let folder = try emptyFolder()
    let id = UUID()
    try Data().write(to: folder.appendingPathComponent(id.uuidString.lowercased() + ".retired"))
    #expect(try RelayFolder.retiredMarks(in: folder) == [id])
}

@Test func holdoutClearingAMissingMarkIsFineAndOthersStay() throws {
    let folder = try emptyFolder()
    let keep = UUID()
    try RelayFolder.retire([keep], in: folder, trash: moveAway)
    try RelayFolder.clearMark(UUID(), in: folder)
    #expect(try RelayFolder.retiredMarks(in: folder) == [keep])
}

@Test func holdoutMarksDoNotLookLikePiecesToImport() throws {
    let folder = try emptyFolder()
    try RelayFolder.retire([UUID()], in: folder, trash: moveAway)
    #expect(try RelayFolder.scan(folder, imported: []) == RelayFolder.Scan())
}

import Foundation
import Testing
@testable import CalendarDomain

private func tokyo() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}
private func at(_ hour: Int, day: Int = 25) -> Date {
    tokyo().date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
}
private func hash(_ n: Int) -> String { String(repeating: String(n % 10), count: 64) }
private func workspace() -> RecordingWorkspace {
    RecordingWorkspace(root: FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)"))
}
private func save(_ workspace: RecordingWorkspace, _ n: Int, _ date: Date, _ text: String = "") throws {
    var document = CalendarDocument(recordingHash: hash(n), originalName: "\(n).m4a", referenceDate: date, timeZoneID: "Asia/Tokyo")
    document.transcript = text
    try workspace.save(document)
}

@Test func onlyTheDaysRecordingsAreListedInTimeOrder() throws {
    let space = workspace()
    try save(space, 1, at(20), "夜")
    try save(space, 2, at(8), "朝")
    try save(space, 3, at(9, day: 26), "翌日")
    let listed = try space.documents(onDayOf: at(12), calendar: tokyo())
    #expect(listed.map(\.transcript) == ["朝", "夜"])
}

@Test func aWorkspaceThatWasNeverUsedHasNoRecordings() throws {
    #expect(try workspace().documents(onDayOf: at(12), calendar: tokyo()).isEmpty)
}

@Test func audioAndUnrelatedFilesAreIgnored() throws {
    let space = workspace()
    try save(space, 4, at(10), "本物")
    try Data("x".utf8).write(to: space.root.appendingPathComponent(hash(4) + ".m4a"))
    try Data("{}".utf8).write(to: space.root.appendingPathComponent("notes.json"))
    #expect(try space.documents(onDayOf: at(12), calendar: tokyo()).map(\.transcript) == ["本物"])
}

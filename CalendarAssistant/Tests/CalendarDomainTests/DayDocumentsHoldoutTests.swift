import Foundation
import Testing
@testable import CalendarDomain

private func zone(_ id: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: id)!
    return calendar
}
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 25, in calendar: Calendar = zone("Asia/Tokyo")) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}
private func hash(_ c: Character) -> String { String(repeating: String(c), count: 64) }
private func workspace() -> RecordingWorkspace {
    RecordingWorkspace(root: FileManager.default.temporaryDirectory.appendingPathComponent("rec-h-\(UUID().uuidString)"))
}
private func save(_ space: RecordingWorkspace, _ c: Character, _ date: Date, _ text: String) throws {
    var document = CalendarDocument(recordingHash: hash(c), originalName: "\(c).m4a", referenceDate: date, timeZoneID: "Asia/Tokyo")
    document.transcript = text
    try space.save(document)
}

@Test func holdoutABrokenOrForeignDocumentIsSkippedNotFatal() throws {
    let space = workspace()
    try save(space, "a", at(9), "残る")
    try Data("壊れた".utf8).write(to: space.root.appendingPathComponent(hash("b") + ".json"))
    // A document saved under another recording's name.
    var moved = CalendarDocument(recordingHash: hash("c"), originalName: "c.m4a", referenceDate: at(10), timeZoneID: "Asia/Tokyo")
    moved.transcript = "名前違い"
    try JSONEncoder().encode(moved).write(to: space.root.appendingPathComponent(hash("d") + ".json"))
    var future = CalendarDocument(recordingHash: hash("e"), originalName: "e.m4a", referenceDate: at(11), timeZoneID: "Asia/Tokyo")
    future.version = 2; future.transcript = "新しい版"
    try JSONEncoder().encode(future).write(to: space.root.appendingPathComponent(hash("e") + ".json"))
    #expect(try space.documents(onDayOf: at(12), calendar: zone("Asia/Tokyo")).map(\.transcript) == ["残る"])
}

@Test func holdoutTheDayFollowsTheCalendarsTimeZoneAndItsBoundaries() throws {
    let space = workspace()
    let newYork = zone("America/New_York")
    try save(space, "1", at(0, 0, day: 25, in: newYork), "始まり")
    try save(space, "2", at(23, 59, day: 25, in: newYork), "終わり")
    try save(space, "3", at(0, 0, day: 26, in: newYork), "翌日")
    #expect(try space.documents(onDayOf: at(12, day: 25, in: newYork), calendar: newYork).map(\.transcript) == ["始まり", "終わり"])
}

@Test func holdoutEqualTimesAreOrderedByRecordingHashAndSubfoldersAreIgnored() throws {
    let space = workspace()
    try save(space, "f", at(9), "f")
    try save(space, "0", at(9), "0")
    let nested = space.root.appendingPathComponent("old")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let other = RecordingWorkspace(root: nested)
    try save(other, "7", at(9), "入れ子")
    #expect(try space.documents(onDayOf: at(12), calendar: zone("Asia/Tokyo")).map(\.transcript) == ["0", "f"])
}

@Test func holdoutUppercaseOrShortNamesAreIgnored() throws {
    let space = workspace()
    try save(space, "5", at(9), "正規")
    let document = CalendarDocument(recordingHash: hash("5"), originalName: "x", referenceDate: at(9), timeZoneID: "Asia/Tokyo")
    try JSONEncoder().encode(document).write(to: space.root.appendingPathComponent("ABC.json"))
    try JSONEncoder().encode(document).write(to: space.root.appendingPathComponent(hash("5").uppercased() + "X.json"))
    #expect(try space.documents(onDayOf: at(12), calendar: zone("Asia/Tokyo")).count == 1)
}

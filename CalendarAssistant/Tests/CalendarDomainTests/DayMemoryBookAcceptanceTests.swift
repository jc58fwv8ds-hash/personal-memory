import Foundation
import Testing
@testable import CalendarDomain

private func tokyo() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 25) -> Date {
    tokyo().date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}
private func freshBook() throws -> DayMemoryBook {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("daybook-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return DayMemoryBook(directory: directory, calendar: tokyo())
}
private let recA = UUID(), recB = UUID()
private func moment(_ summary: String, _ time: Date, _ recording: UUID, edited: Bool = false) -> DayMoment {
    DayMoment(occurredAt: time, summary: summary, sourceQuote: summary, importance: 50, tags: [], recordingID: recording, userEdited: edited)
}

@Test func aDayWithNoFileIsEmpty() throws {
    #expect(try freshBook().load(day: at(12)).isEmpty)
}

@Test func mergedMomentsAreSavedSortedAndLoadBack() throws {
    let book = try freshBook()
    let saved = try book.merge([moment("夜", at(21), recA), moment("朝", at(7), recA)], day: at(12))
    #expect(saved.map(\.summary) == ["朝", "夜"])
    #expect(try book.load(day: at(3)) == saved)
    #expect(FileManager.default.fileExists(atPath: book.directory.appendingPathComponent("2026-10-25.json").path))
}

@Test func aNewSummaryOfARecordingReplacesItsOldMomentsButKeepsOtherRecordings() throws {
    let book = try freshBook()
    _ = try book.merge([moment("A古い", at(8), recA), moment("B", at(9), recB)], day: at(12))
    let saved = try book.merge([moment("A新しい", at(8, 30), recA)], day: at(12))
    #expect(saved.map(\.summary) == ["A新しい", "B"])
}

@Test func theUsersOwnEditsSurviveANewSummary() throws {
    let book = try freshBook()
    try book.save([moment("自分で直した", at(8), recA, edited: true), moment("A古い", at(10), recA)], day: at(12))
    let saved = try book.merge([moment("A新しい", at(9), recA)], day: at(12))
    #expect(saved.map(\.summary) == ["自分で直した", "A新しい"])
}

@Test func anUnreadableFileIsNeverWrittenOver() throws {
    let book = try freshBook()
    let file = book.directory.appendingPathComponent("2026-10-25.json")
    try Data("壊れた中身".utf8).write(to: file)
    #expect(throws: DayMemoryBook.Failure.unreadable) { try book.merge([moment("朝", at(7), recA)], day: at(12)) }
    #expect(try Data(contentsOf: file) == Data("壊れた中身".utf8))
}

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
private func freshBook(_ calendar: Calendar = zone("Asia/Tokyo")) throws -> DayMemoryBook {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("daybook-h-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return DayMemoryBook(directory: directory, calendar: calendar)
}
private func moment(_ summary: String, _ time: Date, _ recording: UUID, edited: Bool = false) -> DayMoment {
    DayMoment(occurredAt: time, summary: summary, sourceQuote: summary, importance: 50, tags: [], recordingID: recording, userEdited: edited)
}

@Test func holdoutAMomentOnAnotherDayIsRejectedAndNothingIsWritten() throws {
    let book = try freshBook()
    let rec = UUID()
    _ = try book.merge([moment("今日", at(10), rec)], day: at(12))
    #expect(throws: DayMemoryBook.Failure.wrongDay) { try book.merge([moment("翌日", at(0, 30, day: 26), rec)], day: at(12)) }
    #expect(throws: DayMemoryBook.Failure.wrongDay) { try book.save([moment("前日", at(23, 59, day: 24), rec)], day: at(12)) }
    #expect(try book.load(day: at(12)).map(\.summary) == ["今日"])
}

@Test func holdoutTheDayFollowsTheCalendarsTimeZone() throws {
    let newYork = zone("America/New_York")
    let book = try freshBook(newYork)
    let late = at(23, 30, day: 25, in: newYork)   // already the 26th in Tokyo and UTC
    _ = try book.merge([moment("夜更け", late, UUID())], day: late)
    #expect(FileManager.default.fileExists(atPath: book.directory.appendingPathComponent("2026-10-25.json").path))
}

@Test func holdoutSaveReplacesTheDayExactlyIncludingDeletions() throws {
    let book = try freshBook()
    let rec = UUID()
    let first = try book.merge([moment("一", at(8), rec), moment("二", at(9), rec)], day: at(12))
    try book.save([first[1]], day: at(12))
    #expect(try book.load(day: at(12)) == [first[1]])
    try book.save([], day: at(12))
    #expect(try book.load(day: at(12)).isEmpty)
}

@Test func holdoutAnUnreadableFileFailsToLoadAndSaveDoesNotTouchOtherDays() throws {
    let book = try freshBook()
    let file = book.directory.appendingPathComponent("2026-10-25.json")
    try Data("[{\"broken\":true}]".utf8).write(to: file)
    #expect(throws: DayMemoryBook.Failure.unreadable) { try book.load(day: at(12)) }
    _ = try book.merge([moment("翌日", at(9, day: 26), UUID())], day: at(9, day: 26))
    #expect(try Data(contentsOf: file) == Data("[{\"broken\":true}]".utf8))
}

@Test func holdoutEditedMomentsOfOtherRecordingsAndEqualTimesKeepTheirOrder() throws {
    let book = try freshBook()
    let recA = UUID(), recB = UUID()
    try book.save([moment("B自分", at(9), recB, edited: true), moment("A古い", at(9), recA)], day: at(12))
    let saved = try book.merge([moment("A新1", at(9), recA), moment("A新2", at(9), recA)], day: at(12))
    #expect(saved.map(\.summary) == ["B自分", "A新1", "A新2"])
    #expect(try book.load(day: at(12)) == saved)
}

@Test func holdoutAMissingDirectoryIsCreatedOnSave() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("daybook-new-\(UUID().uuidString)/days")
    let book = DayMemoryBook(directory: directory, calendar: zone("Asia/Tokyo"))
    _ = try book.merge([moment("朝", at(7), UUID())], day: at(12))
    #expect(try book.load(day: at(12)).count == 1)
}

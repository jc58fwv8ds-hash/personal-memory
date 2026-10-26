// Local Factory 課題 pm-day-07 の見える試験と隠し試験(HarnessTasks/pm-day-07)。
import Foundation
import Testing
@testable import CalendarDomain
fileprivate func tokyo() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}

fileprivate func at(_ day: Int, _ hour: Int) -> Date {
    tokyo().date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
}

fileprivate func book() -> DaySuggestionBook {
    DaySuggestionBook(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), calendar: tokyo())
}

fileprivate func memo(_ title: String, quote: String) -> ItemSuggestion {
    ItemSuggestion(kind: .memo, title: title, body: "", sourceQuote: quote)
}

@Test func mergedSuggestionsAreSavedAndLoaded() throws {
    let book = book()
    let items = [memo("買い物", quote: "牛乳と卵"), memo("企画", quote: "通知を夜に")]
    #expect(try book.merge(items, day: at(26, 9)) == items)
    #expect(try book.load(day: at(26, 22)) == items)
    #expect(FileManager.default.fileExists(atPath: book.directory.appendingPathComponent("2026-10-26.suggestions.json").path))
}

@Test func aSuggestionFromTheSameWordsIsNotAddedTwice() throws {
    let book = book()
    let first = memo("買い物", quote: "牛乳と卵")
    try book.merge([first], day: at(26, 9))
    let again = try book.merge([memo("買い物リスト", quote: "牛乳と卵"), memo("企画", quote: "通知を夜に")], day: at(26, 9))
    #expect(again.map(\.title) == ["買い物", "企画"])
}

@Test func updateReplacesByID() throws {
    let book = book()
    var item = memo("買い物", quote: "牛乳と卵")
    try book.merge([item], day: at(26, 9))
    item.state = .dismissed
    #expect(try book.update(item, day: at(26, 9)) == [item])
    #expect(try book.load(day: at(26, 9))[0].state == .dismissed)
}

@Test func holdoutNothingSavedIsEmpty() throws {
    #expect(try book().load(day: at(26, 9)).isEmpty)
}

@Test func holdoutDismissedAndEditedItemsSurviveAskingAgain() throws {
    let book = book()
    var dismissed = memo("買い物", quote: "牛乳と卵")
    var edited = ItemSuggestion(kind: .calendar, title: "歯医者", body: "", sourceQuote: "10時から歯医者")
    try book.merge([dismissed, edited], day: at(26, 9))
    dismissed.state = .dismissed; try book.update(dismissed, day: at(26, 9))
    edited.title = "歯医者(駅前)"; edited.start = at(27, 10); edited.end = at(27, 11); try book.update(edited, day: at(26, 9))
    let again = try book.merge([memo("買い物", quote: "牛乳と卵"),
                                ItemSuggestion(kind: .calendar, title: "歯医者", body: "", sourceQuote: "10時から歯医者")], day: at(26, 9))
    #expect(again == [dismissed, edited])
}

@Test func holdoutTheSameWordsAsAnotherKindAreStillAdded() throws {
    let book = book()
    try book.merge([memo("歯医者", quote: "10時から歯医者")], day: at(26, 9))
    let result = try book.merge([ItemSuggestion(kind: .calendar, title: "歯医者", body: "", sourceQuote: "10時から歯医者")], day: at(26, 9))
    #expect(result.map(\.kind) == [.memo, .calendar])
}

@Test func holdoutRepeatsWithinOneMergeAreAddedOnce() throws {
    let result = try book().merge([memo("a", quote: "同じ言葉"), memo("b", quote: "同じ言葉")], day: at(26, 9))
    #expect(result.map(\.title) == ["a"])
}

@Test func holdoutUpdatingAnUnknownIDThrowsAndChangesNothing() throws {
    let book = book()
    let item = memo("買い物", quote: "牛乳と卵")
    try book.merge([item], day: at(26, 9))
    #expect(throws: DaySuggestionBook.NotFound.self) { try book.update(memo("x", quote: "y"), day: at(26, 9)) }
    #expect(try book.load(day: at(26, 9)) == [item])
}

@Test func holdoutDaysAreSeparateAndAnUnreadableFileThrows() throws {
    let book = book()
    try book.merge([memo("26日", quote: "a")], day: at(26, 9))
    try book.merge([memo("25日", quote: "a")], day: at(25, 23))
    #expect(try book.load(day: at(26, 1)).map(\.title) == ["26日"])
    #expect(try book.load(day: at(25, 1)).map(\.title) == ["25日"])
    try Data("broken".utf8).write(to: book.directory.appendingPathComponent("2026-10-24.suggestions.json"))
    #expect(throws: (any Error).self) { try book.load(day: at(24, 9)) }
    #expect(throws: (any Error).self) { try book.merge([memo("x", quote: "x")], day: at(24, 9)) }
}

/// Added after the run (2026-10-27): the generated file name followed the Mac's time zone, not the calendar's.
@Test func holdoutTheFileNameUsesTheCalendarsTimeZone() throws {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let book = DaySuggestionBook(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), calendar: utc)
    try book.merge([memo("x", quote: "y")], day: at(26, 8))   // 2026-10-25 23:00 UTC
    #expect(FileManager.default.fileExists(atPath: book.directory.appendingPathComponent("2026-10-25.suggestions.json").path))
}

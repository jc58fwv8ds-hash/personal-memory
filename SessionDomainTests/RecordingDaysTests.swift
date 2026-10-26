// Local Factory 課題 pm-day-04 の見える試験と隠し試験(HarnessTasks/pm-day-04)。
import Foundation
import Testing
@testable import SessionDomain
fileprivate struct Piece: Sendable, Equatable { let name: String; let start: Date; let end: Date }

fileprivate func tokyo() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}

/// 2026-10-26 hh:mm in Tokyo.
fileprivate func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    tokyo().date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

fileprivate func group(_ pieces: [Piece]) -> [RecordingDay<Piece>] {
    RecordingDays.group(pieces, calendar: tokyo(), start: \.start, end: \.end)
}

@Test func piecesOfOneDayBecomeOneDay() {
    let pieces = [Piece(name: "b", start: at(26, 8, 55), end: at(26, 9, 5)),
                  Piece(name: "a", start: at(26, 8, 45), end: at(26, 8, 55))]
    let days = group(pieces)
    #expect(days.count == 1)
    #expect(days[0].pieces.map(\.name) == ["a", "b"])
    #expect(days[0].day == tokyo().startOfDay(for: at(26, 12, 0)))
    #expect(days[0].start == at(26, 8, 45))
    #expect(days[0].end == at(26, 9, 5))
    #expect(days[0].seconds == 1200)
}

@Test func newestDayFirst() {
    let days = group([Piece(name: "old", start: at(24, 10, 0), end: at(24, 10, 10)),
                      Piece(name: "new", start: at(26, 10, 0), end: at(26, 10, 10))])
    #expect(days.map { $0.pieces[0].name } == ["new", "old"])
}

@Test func nothingGivesNoDays() {
    #expect(group([]).isEmpty)
}

@Test func holdoutAPieceAcrossMidnightBelongsToTheDayItStarted() {
    let days = group([Piece(name: "late", start: at(25, 23, 55), end: at(26, 0, 5)),
                      Piece(name: "morning", start: at(26, 7, 0), end: at(26, 7, 10))])
    #expect(days.map { $0.pieces.map(\.name) } == [["morning"], ["late"]])
    #expect(days[1].end == at(26, 0, 5))
    #expect(days[1].seconds == 600)
}

@Test func holdoutTheCalendarsTimeZoneDecidesTheDay() {
    // 2026-10-26 08:00 in Tokyo is 2026-10-25 23:00 UTC.
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let piece = Piece(name: "x", start: at(26, 8, 0), end: at(26, 8, 10))
    let days = RecordingDays.group([piece], calendar: utc, start: \.start, end: \.end)
    #expect(days[0].day == utc.startOfDay(for: at(26, 8, 0)))
    #expect(utc.component(.day, from: days[0].day) == 25)
}

@Test func holdoutAPieceEndingBeforeItStartsCountsAsZero() {
    let days = group([Piece(name: "odd", start: at(26, 9, 0), end: at(26, 8, 50)),
                      Piece(name: "ok", start: at(26, 10, 0), end: at(26, 10, 10))])
    #expect(days[0].seconds == 600)
    #expect(days[0].start == at(26, 9, 0))
    #expect(days[0].end == at(26, 10, 10))
}

@Test func holdoutSameStartKeepsTheGivenOrder() {
    let days = group([Piece(name: "first", start: at(26, 9, 0), end: at(26, 9, 10)),
                      Piece(name: "second", start: at(26, 9, 0), end: at(26, 9, 5)),
                      Piece(name: "earlier", start: at(26, 8, 0), end: at(26, 8, 5))])
    #expect(days[0].pieces.map(\.name) == ["earlier", "first", "second"])
}

@Test func holdoutManyDaysAreAllKeptNewestFirst() {
    let pieces = (20...26).reversed().map { Piece(name: "d\($0)", start: at($0, 12, 0), end: at($0, 12, 10)) }
    let days = group(pieces.shuffled())
    #expect(days.map { $0.pieces[0].name } == (20...26).reversed().map { "d\($0)" })
}

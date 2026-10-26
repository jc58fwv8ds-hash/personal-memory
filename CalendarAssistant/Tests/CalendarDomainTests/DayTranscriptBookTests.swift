// Local Factory 課題 pm-day-05 の見える試験と隠し試験(HarnessTasks/pm-day-05)。
import Foundation
import Testing
@testable import CalendarDomain
fileprivate func tokyo() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}

fileprivate func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    tokyo().date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

fileprivate func book() -> DayTranscriptBook {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return DayTranscriptBook(directory: directory, calendar: tokyo())
}

@Test func aRecordedPieceIsSavedAndLoaded() throws {
    let book = book()
    let id = UUID()
    try book.record("  おはようございます \n", piece: id, start: at(26, 8, 45), day: at(26, 8, 45))
    let loaded = try book.load(day: at(26, 20, 0))
    #expect(loaded.pieces[id.uuidString] == PieceTranscript(start: at(26, 8, 45), text: "おはようございます"))
    #expect(FileManager.default.fileExists(atPath: book.directory.appendingPathComponent("2026-10-26.transcript.json").path))
}

@Test func missingListsPiecesWithoutText() throws {
    let book = book()
    let a = UUID(), b = UUID(), c = UUID()
    try book.record("a", piece: b, start: at(26, 9, 0), day: at(26, 9, 0))
    #expect(try book.missing([a, b, c], day: at(26, 9, 0)) == [a, c])
}

@Test func theDaysTextIsInTimeOrderWithClockTimes() throws {
    let transcript = DayTranscript(pieces: [
        UUID().uuidString: PieceTranscript(start: at(26, 9, 5), text: "会議の準備"),
        UUID().uuidString: PieceTranscript(start: at(26, 8, 45), text: "おはよう"),
    ])
    #expect(DayTranscriptBook.text(of: transcript, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
            == "[08:45] おはよう\n[09:05] 会議の準備")
}

@Test func holdoutNothingSavedLoadsEmpty() throws {
    #expect(try book().load(day: at(26, 9, 0)) == DayTranscript())
}

@Test func holdoutDaysAreSeparateFiles() throws {
    let book = book()
    let a = UUID(), b = UUID()
    try book.record("26日", piece: a, start: at(26, 9, 0), day: at(26, 9, 0))
    try book.record("25日", piece: b, start: at(25, 23, 0), day: at(25, 23, 0))
    #expect(Set(try book.load(day: at(26, 1, 0)).pieces.keys) == [a.uuidString])
    #expect(Set(try book.load(day: at(25, 1, 0)).pieces.keys) == [b.uuidString])
    #expect(FileManager.default.fileExists(atPath: book.directory.appendingPathComponent("2026-10-25.transcript.json").path))
}

@Test func holdoutRecordingAgainReplacesThatPieceOnly() throws {
    let book = book()
    let a = UUID(), b = UUID()
    try book.record("one", piece: a, start: at(26, 9, 0), day: at(26, 9, 0))
    try book.record("two", piece: b, start: at(26, 9, 10), day: at(26, 9, 0))
    let result = try book.record("ONE", piece: a, start: at(26, 9, 0), day: at(26, 9, 0))
    #expect(result.pieces[a.uuidString]?.text == "ONE")
    #expect(result.pieces[b.uuidString]?.text == "two")
    #expect(try book.load(day: at(26, 9, 0)) == result)
}

@Test func holdoutSilentPiecesCountAsDoneButAreNotShown() throws {
    let book = book()
    let quiet = UUID(), spoken = UUID()
    try book.record("   ", piece: quiet, start: at(26, 10, 0), day: at(26, 10, 0))
    let day = try book.record("話した", piece: spoken, start: at(26, 10, 10), day: at(26, 10, 0))
    #expect(try book.missing([quiet, spoken], day: at(26, 10, 0)).isEmpty)
    #expect(DayTranscriptBook.text(of: day, timeZone: TimeZone(identifier: "Asia/Tokyo")!) == "[10:10] 話した")
}

@Test func holdoutAnUnreadableFileThrowsInsteadOfStartingOver() throws {
    let book = book()
    try FileManager.default.createDirectory(at: book.directory, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: book.directory.appendingPathComponent("2026-10-26.transcript.json"))
    #expect(throws: (any Error).self) { try book.load(day: at(26, 9, 0)) }
    #expect(throws: (any Error).self) { try book.record("x", piece: UUID(), start: at(26, 9, 0), day: at(26, 9, 0)) }
}

@Test func holdoutClockTimesUseTheGivenTimeZone() throws {
    let transcript = DayTranscript(pieces: [UUID().uuidString: PieceTranscript(start: at(26, 8, 45), text: "x")])
    #expect(DayTranscriptBook.text(of: transcript, timeZone: TimeZone(identifier: "UTC")!) == "[23:45] x")
}

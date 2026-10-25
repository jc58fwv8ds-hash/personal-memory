import Foundation
import Testing
@testable import CalendarDomain

private let recID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
private let rec = DayRecording(id: recID, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                               transcript: "朝は雨だった。昼に田中さんと打ち合わせ。夜はカレーを作った。")

private func moment(_ fields: [String: Any]) -> [String: Any] {
    var base: [String: Any] = ["recording": recID.uuidString, "offsetSeconds": 0, "summary": "雨",
                               "sourceQuote": "朝は雨だった", "importance": 10, "tags": []]
    for (key, value) in fields { base[key] = value }
    return base
}
private func decode(_ moments: [[String: Any]]) throws -> [DayMoment] {
    try DayMemoryDecoder.decode(try JSONSerialization.data(withJSONObject: ["moments": moments]), recordings: [rec])
}

@Test func holdoutNegativeOffsetIsRejected() {
    #expect(throws: DayMemoryDecoder.InvalidDayMemory.self) { try decode([moment(["offsetSeconds": -1])]) }
}

@Test func holdoutOffsetBeyondSixHoursIsRejected() throws {
    #expect(throws: DayMemoryDecoder.InvalidDayMemory.self) { try decode([moment(["offsetSeconds": 21_601])]) }
    #expect(try decode([moment(["offsetSeconds": 21_600])]).count == 1)
}

@Test func holdoutMissingOffsetMeansTheStartOfTheRecording() throws {
    var fields = moment([:]); fields.removeValue(forKey: "offsetSeconds")
    #expect(try decode([fields]).first?.occurredAt == rec.startedAt)
}

@Test func holdoutBlankQuoteOrSummaryIsRejected() {
    #expect(throws: DayMemoryDecoder.InvalidDayMemory.self) { try decode([moment(["sourceQuote": "  "])]) }
    #expect(throws: DayMemoryDecoder.InvalidDayMemory.self) { try decode([moment(["summary": " \n"])]) }
    #expect(throws: DayMemoryDecoder.InvalidDayMemory.self) { try decode([moment(["summary": String(repeating: "あ", count: 301)])]) }
}

@Test func holdoutTooManyMomentsOrTooLargeAnswerIsRejected() throws {
    #expect(throws: DayMemoryDecoder.InvalidDayMemory.self) { try decode(Array(repeating: moment([:]), count: 31)) }
    #expect(try decode(Array(repeating: moment([:]), count: 30)).count == 30)
    let huge = Data(repeating: UInt8(ascii: " "), count: 65_537)
    #expect(throws: DayMemoryDecoder.InvalidDayMemory.self) { try DayMemoryDecoder.decode(huge, recordings: [rec]) }
}

@Test func holdoutBrokenJSONIsRejected() {
    #expect(throws: DayMemoryDecoder.InvalidDayMemory.self) { try DayMemoryDecoder.decode(Data("{\"moments\":[".utf8), recordings: [rec]) }
}

@Test func holdoutTiesKeepTheModelsOrderAndAtMostFiveTagsAreKept() throws {
    let result = try decode([moment(["summary": "打ち合わせ", "sourceQuote": "田中さんと打ち合わせ", "tags": ["a", "b", "c", "d", "e", "f"]]),
                             moment(["summary": "カレー", "sourceQuote": "夜はカレーを作った", "importance": -5])])
    #expect(result.map(\.summary) == ["打ち合わせ", "カレー"])
    #expect(result[0].tags == ["a", "b", "c", "d", "e"])
    #expect(result[1].importance == 0)
    #expect(result[0].id != result[1].id)
}

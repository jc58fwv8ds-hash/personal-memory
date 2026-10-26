// Local Factory 課題 pm-day-06 の見える試験と隠し試験(HarnessTasks/pm-day-06)。
import Foundation
import Testing
@testable import CalendarDomain
fileprivate let transcript = "[08:45] 明日の10時から歯医者に行く。\n[09:05] 牛乳と卵を買っておくこと。\n[09:20] 企画書のアイデア、通知を夜にまとめる。"

fileprivate func decode(_ json: String) throws -> ItemSuggestionDecoder.Decoded {
    try ItemSuggestionDecoder.decode(Data(json.utf8), transcript: transcript)
}

@Test func calendarAndMemoItemsAreRead() throws {
    let result = try decode("""
    {"items":[
     {"kind":"calendar","title":"歯医者","body":"","sourceQuote":"明日の10時から歯医者に行く","start":"2026-10-27T10:00:00+09:00","end":"2026-10-27T11:00:00+09:00"},
     {"kind":"memo","title":"買い物","body":"牛乳と卵","sourceQuote":"牛乳と卵を買っておくこと","start":null,"end":null}
    ]}
    """)
    #expect(result.skipped == 0)
    #expect(result.items.map(\.kind) == [.calendar, .memo])
    #expect(result.items[0].start == ISO8601DateFormatter().date(from: "2026-10-27T01:00:00Z"))
    #expect(result.items[0].end == ISO8601DateFormatter().date(from: "2026-10-27T02:00:00Z"))
    #expect(result.items[1].body == "牛乳と卵")
    #expect(result.items.allSatisfy { $0.state == .suggested })
}

@Test func aQuoteNotInTheTranscriptDropsThatItemOnly() throws {
    let result = try decode("""
    {"items":[
     {"kind":"memo","title":"作り話","body":"","sourceQuote":"そんなことは言っていない"},
     {"kind":"memo","title":"企画","body":"","sourceQuote":"通知を夜にまとめる"}
    ]}
    """)
    #expect(result.items.map(\.title) == ["企画"])
    #expect(result.skipped == 1)
}

@Test func notJSONIsAnInvalidAnswer() {
    #expect(throws: ItemSuggestionDecoder.InvalidAnswer.self) { try decode("はい、まとめました") }
}

@Test func holdoutUnknownKindsAndBadTitlesAreSkipped() throws {
    let long = String(repeating: "あ", count: 201)
    let result = try decode("""
    {"items":[
     {"kind":"todo","title":"x","body":"","sourceQuote":"牛乳と卵"},
     {"kind":"memo","title":"   ","body":"","sourceQuote":"牛乳と卵"},
     {"kind":"memo","title":"\(long)","body":"","sourceQuote":"牛乳と卵"},
     {"kind":"memo","title":" 買い物 ","body":" 牛乳 ","sourceQuote":" 牛乳と卵 "}
    ]}
    """)
    #expect(result.skipped == 3)
    #expect(result.items.map(\.title) == ["買い物"])
    #expect(result.items[0].body == "牛乳")
    #expect(result.items[0].sourceQuote == "牛乳と卵")
}

@Test func holdoutMemosNeverKeepTimes() throws {
    let result = try decode("""
    {"items":[{"kind":"memo","title":"買い物","sourceQuote":"牛乳と卵","start":"2026-10-27T10:00:00+09:00","end":"2026-10-27T11:00:00+09:00"}]}
    """)
    #expect(result.items[0].start == nil && result.items[0].end == nil)
    #expect(result.items[0].body == "")
}

@Test func holdoutUnusableTimesAreLeftForTheUserNotGuessed() throws {
    let result = try decode("""
    {"items":[
     {"kind":"calendar","title":"a","sourceQuote":"歯医者","start":"2026-10-27T10:00:00+09:00","end":null},
     {"kind":"calendar","title":"b","sourceQuote":"歯医者","start":"明日","end":"明後日"},
     {"kind":"calendar","title":"c","sourceQuote":"歯医者","start":"2026-10-27T11:00:00+09:00","end":"2026-10-27T10:00:00+09:00"},
     {"kind":"calendar","title":"d","sourceQuote":"歯医者","start":"2026-10-27T10:00:00+09:00","end":"2026-11-05T10:00:00+09:00"},
     {"kind":"calendar","title":"e","sourceQuote":"歯医者","start":"2026-10-27T10:00:00.500+09:00","end":"2026-10-27T10:30:00Z"}
    ]}
    """)
    #expect(result.skipped == 0)
    #expect(result.items.prefix(4).allSatisfy { $0.start == nil && $0.end == nil })
    #expect(result.items[4].start != nil && result.items[4].end != nil)
}

@Test func holdoutRepeatedItemsAreKeptOnce() throws {
    let item = #"{"kind":"memo","title":"買い物","body":"","sourceQuote":"牛乳と卵"}"#
    let other = #"{"kind":"calendar","title":"買い物","body":"","sourceQuote":"牛乳と卵"}"#
    let result = try decode(#"{"items":["# + [item, item, other].joined(separator: ",") + "]}")
    #expect(result.items.map(\.kind) == [.memo, .calendar])
    #expect(result.skipped == 1)
    #expect(Set(result.items.map(\.id)).count == 2)
}

@Test func holdoutTooLargeOrTooManyIsAnInvalidAnswer() {
    let many = (0..<41).map { _ in #"{"kind":"memo","title":"t","sourceQuote":"牛乳"}"# }.joined(separator: ",")
    #expect(throws: ItemSuggestionDecoder.InvalidAnswer.self) { try decode(#"{"items":["# + many + "]}") }
    let big = Data((#"{"items":[],"pad":""# + String(repeating: "x", count: 70_000) + #""}"#).utf8)
    #expect(throws: ItemSuggestionDecoder.InvalidAnswer.self) { try ItemSuggestionDecoder.decode(big, transcript: transcript) }
    #expect(throws: ItemSuggestionDecoder.InvalidAnswer.self) { try decode(#"{"events":[]}"#) }
}

@Test func holdoutAnItemThatIsNotAnObjectIsSkipped() throws {
    let result = try decode(#"{"items":["memo", 3, {"kind":"memo","title":"企画","sourceQuote":"企画書のアイデア"}]}"#)
    #expect(result.items.count == 1)
    #expect(result.skipped == 2)
}

@Test func holdoutAnEmptyListIsFine() throws {
    #expect(try decode(#"{"items":[]}"#) == ItemSuggestionDecoder.Decoded(items: [], skipped: 0))
}

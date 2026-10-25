import Foundation
import Testing
@testable import CalendarDomain

private let morningID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
private let eveningID = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
private let morning = DayRecording(id: morningID, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                   transcript: "駅前のパン屋で新作のメロンパンを買った。午後は企画書を仕上げる。")
private let evening = DayRecording(id: eveningID, startedAt: Date(timeIntervalSince1970: 1_800_030_000),
                                   transcript: "夕方、母に電話して来週の旅行の話をした。")

private func json(_ moments: [[String: Any]]) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["moments": moments])
}

@Test func momentsComeFromTheirRecordingAndAreSortedByTime() throws {
    let data = try json([
        ["recording": eveningID.uuidString, "offsetSeconds": 5, "summary": "母と旅行の相談", "sourceQuote": "母に電話して来週の旅行の話をした", "importance": 70, "tags": ["家族"]],
        ["recording": morningID.uuidString, "offsetSeconds": 0, "summary": "メロンパンを買った", "sourceQuote": "新作のメロンパンを買った", "importance": 30, "tags": ["買い物"]],
    ])
    let moments = try DayMemoryDecoder.decode(data, recordings: [morning, evening])
    #expect(moments.map(\.summary) == ["メロンパンを買った", "母と旅行の相談"])
    #expect(moments[0].recordingID == morningID)
    #expect(moments[1].occurredAt == evening.startedAt.addingTimeInterval(5))
    #expect(moments.allSatisfy { !$0.userEdited })
}

@Test func aQuoteThatIsNotInTheTranscriptRejectsTheAnswer() throws {
    let data = try json([["recording": morningID.uuidString, "offsetSeconds": 0, "summary": "パンを買った",
                          "sourceQuote": "クロワッサンを買った", "importance": 30, "tags": []]])
    #expect(throws: DayMemoryDecoder.InvalidDayMemory.self) { try DayMemoryDecoder.decode(data, recordings: [morning]) }
}

@Test func anUnknownRecordingRejectsTheAnswer() throws {
    let data = try json([["recording": UUID().uuidString, "offsetSeconds": 0, "summary": "パンを買った",
                          "sourceQuote": "新作のメロンパンを買った", "importance": 30, "tags": []]])
    #expect(throws: DayMemoryDecoder.InvalidDayMemory.self) { try DayMemoryDecoder.decode(data, recordings: [morning]) }
}

@Test func importanceIsClampedAndTagsAreCleaned() throws {
    let data = try json([["recording": morningID.uuidString, "offsetSeconds": 0, "summary": " 企画書 ",
                          "sourceQuote": "午後は企画書を仕上げる", "importance": 250,
                          "tags": [" 仕事", "仕事", "", "締め切り"]]])
    let moment = try #require(try DayMemoryDecoder.decode(data, recordings: [morning]).first)
    #expect(moment.importance == 100)
    #expect(moment.tags == ["仕事", "締め切り"])
    #expect(moment.summary == "企画書")
}

@Test func noMomentsIsAValidAnswer() throws {
    #expect(try DayMemoryDecoder.decode(try json([]), recordings: [morning]).isEmpty)
}

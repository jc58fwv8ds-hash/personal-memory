import Foundation
import Testing
@testable import CalendarDomain

struct ProposalDecoderTests {
    let transcript = "明日の午後3時から4時に歯医者。買い物もしよう。"
    func payload(_ event: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["events": [event]])
    }
    var event: [String: Any] { ["title": "歯医者", "sourceQuote": "明日の午後3時から4時に歯医者。",
        "start": "2026-09-14T15:00:00+09:00", "end": "2026-09-14T16:00:00+09:00", "notes": ""] }

    @Test func groundedDraftStillNeedsHumanConfirmation() throws {
        let drafts = try ProposalDecoder.decode(payload(event), transcript: transcript)
        #expect(drafts.count == 1)
        #expect(drafts[0].start != nil)
        #expect(!drafts[0].canRegister)
        var confirmed = drafts[0]; confirmed.dateConfirmed = true
        #expect(confirmed.canRegister)
    }
    @Test func undatedTaskRemainsUndated() throws {
        var value = event; value["start"] = NSNull(); value["end"] = NSNull()
        let draft = try ProposalDecoder.decode(payload(value), transcript: transcript)[0]
        #expect(draft.start == nil && draft.end == nil && !draft.canRegister)
    }
    @Test(arguments: ["quote", "emptyTitle", "badDate", "reverse", "noZone", "oneDate", "oversize", "tooMany"])
    func rejectsUnsafeResponse(kind: String) throws {
        var value = event
        switch kind {
        case "quote": value["sourceQuote"] = "存在しない予定"
        case "emptyTitle": value["title"] = "  "
        case "badDate": value["start"] = "tomorrow"
        case "reverse": value["end"] = "2026-09-14T14:00:00+09:00"
        case "noZone": value["start"] = "2026-09-14T15:00:00"
        case "oneDate": value["end"] = NSNull()
        default: break
        }
        let data: Data
        if kind == "oversize" { data = Data(repeating: 32, count: 65_537) }
        else if kind == "tooMany" {
            data = try JSONSerialization.data(withJSONObject: ["events": Array(repeating: event, count: 13)])
        } else { data = try payload(value) }
        #expect(throws: (any Error).self) { try ProposalDecoder.decode(data, transcript: transcript) }
    }
    @Test func emptyResultIsNotFabricated() throws {
        #expect(try ProposalDecoder.decode(Data("{\"events\":[]}".utf8), transcript: "雑談") == [])
    }
}

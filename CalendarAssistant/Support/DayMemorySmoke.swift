import Foundation
import CalendarDomain

/// Opt-in real local-model probe for the day's memory, synthetic text only. Never runs with swift test, never writes files.
@main struct DayMemorySmoke {
    static func main() async throws {
        let start = ISO8601DateFormatter().date(from: "2026-10-25T08:00:00+09:00")!
        let recording = DayRecording(id: UUID(), startedAt: start, transcript:
            "朝、駅前のパン屋で新作のメロンパンを買った。昼は田中さんと来月の展示会の打ち合わせをして、ポスターは私が作ることになった。夜は母に電話して、週末に実家へ帰ると伝えた。")
        let began = Date()
        let moments = try await LocalDayMemoryService().moments(of: recording, timeZoneID: "Asia/Tokyo",
                                                                 model: LocalProposalService.defaultModel)
        for moment in moments { print("\(moment.importance)\t\(moment.summary)\t「\(moment.sourceQuote)」\t\(moment.tags)") }
        guard (2...8).contains(moments.count), moments.allSatisfy({ recording.transcript.contains($0.sourceQuote) }) else {
            throw CalendarFlowError.message("Synthetic day memory failed: \(moments.count) moments.")
        }
        print("Synthetic day memory passed: \(moments.count) grounded moments. Seconds: \(Date().timeIntervalSince(began))")
    }
}

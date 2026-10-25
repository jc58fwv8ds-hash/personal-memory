import Foundation
import CalendarDomain

/// Opt-in real local-model probe, synthetic text only. Never runs with swift test, never writes Calendar.
@main struct ProposalSmoke {
    static func main() async throws {
        let formatter = ISO8601DateFormatter()
        let reference = formatter.date(from: "2026-09-13T18:00:00+09:00")!
        let started = Date()
        let drafts = try await LocalProposalService().propose(
            transcript: "明日の午後3時から4時まで歯医者に行く予定です。今日は晴れでした。",
            reference: reference, timeZoneID: "Asia/Tokyo", model: LocalProposalService.defaultModel)
        guard drafts.count == 1, drafts[0].title.contains("歯"),
              drafts[0].start == formatter.date(from: "2026-09-14T15:00:00+09:00"),
              drafts[0].end == formatter.date(from: "2026-09-14T16:00:00+09:00"),
              !drafts[0].canRegister else {
            print(String(decoding: try JSONEncoder().encode(drafts), as: UTF8.self))
            throw CalendarFlowError.message("Synthetic live model acceptance failed. No calendar changes.")
        }
        print("Synthetic local proposal passed: 1 grounded draft; relative date correct; human confirmation required. Seconds: \(Date().timeIntervalSince(started))")
    }
}

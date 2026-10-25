import Foundation

/// Deterministic validation after local generation; never grants registration authority.
public enum ProposalDecoder {
    private struct Response: Decodable { let events: [Event] }
    private struct Event: Decodable {
        let title: String
        let sourceQuote: String
        let start: String?
        let end: String?
        let notes: String
    }
    public static func decode(_ data: Data, transcript: String) throws -> [CalendarProposal] {
        guard data.count <= 65_536 else { throw InvalidProposal() }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw InvalidProposal() }
        guard response.events.count <= 12 else { throw InvalidProposal() }
        return try response.events.map { event in
            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 200, !event.sourceQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  transcript.contains(event.sourceQuote), event.notes.count <= 4000 else { throw InvalidProposal() }
            let start = try event.start.map(parseDate)
            let end = try event.end.map(parseDate)
            switch (start, end) {
            case (nil, nil): break
            case let (start?, end?) where end > start && end.timeIntervalSince(start) <= 7 * 86400: break
            default: throw InvalidProposal()
            }
            return CalendarProposal(title: title, sourceQuote: event.sourceQuote, start: start, end: end, notes: event.notes)
        }
    }
    private static func parseDate(_ value: String) throws -> Date {
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { throw InvalidProposal() }
        let strict = DateFormatter()
        strict.locale = Locale(identifier: "en_US_POSIX")
        strict.calendar = Calendar(identifier: .gregorian)
        strict.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        strict.isLenient = false
        guard strict.date(from: value) != nil, let date = ISO8601DateFormatter().date(from: value) else {
            throw InvalidProposal()
        }
        return date
    }
    public struct InvalidProposal: LocalizedError {
        public var errorDescription: String? {
            "AIの候補に、原文と一致しない引用や不正な日時がありました。登録せず停止しました。文章を確認して再提案できます。"
        }
    }
}

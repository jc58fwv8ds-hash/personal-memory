import Foundation

/// Checks what the local model returned for a stretch of the day's transcript. The model answers with JSON only:
/// {"items":[{"kind":"calendar","title":"…","body":"…","sourceQuote":"…","start":"2026-10-27T10:00:00+09:00","end":"…"}]}
/// One bad item is dropped (and counted), not the whole answer: a day has many items.
public enum ItemSuggestionDecoder {
    public struct Decoded: Equatable, Sendable {
        public var items: [ItemSuggestion]
        public var skipped: Int
        public init(items: [ItemSuggestion], skipped: Int) { self.items = items; self.skipped = skipped }
    }

    public struct InvalidAnswer: Error, Equatable {
        public init() {}
    }

    private static func parseDate(_ s: String) -> Date? {
        guard s.contains("+") || s.contains("-") else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }

    public static func decode(_ data: Data, transcript: String) throws -> Decoded {
        guard data.count <= 65536 else { throw InvalidAnswer() }
        guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw InvalidAnswer() }
        guard let rawItems = top["items"] as? [Any] else { throw InvalidAnswer() }
        guard rawItems.count <= 40 else { throw InvalidAnswer() }
        var items: [ItemSuggestion] = []
        var skipped = 0
        var seen = Set<String>()
        for raw in rawItems {
            guard let obj = raw as? [String: Any] else { skipped += 1; continue }
            guard let kindStr = obj["kind"] as? String, let kind = ItemSuggestion.Kind(rawValue: kindStr) else { skipped += 1; continue }
            guard let titleRaw = obj["title"] as? String else { skipped += 1; continue }
            let title = titleRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 1, title.count <= 200 else { skipped += 1; continue }
            let body = (obj["body"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard body.count <= 4000 else { skipped += 1; continue }
            guard let quoteRaw = obj["sourceQuote"] as? String else { skipped += 1; continue }
            let quote = quoteRaw.trimmingCharacters(in: .whitespaces)
            guard !quote.isEmpty, transcript.contains(quote) else { skipped += 1; continue }
            let key = kind.rawValue + "\u{0}" + title + "\u{0}" + quote
            guard !seen.contains(key) else { skipped += 1; continue }
            seen.insert(key)
            var start: Date? = nil
            var end: Date? = nil
            if kind == .calendar, let sRaw = obj["start"] as? String, let eRaw = obj["end"] as? String,
               let s = parseDate(sRaw), let e = parseDate(eRaw), e > s, e.timeIntervalSince(s) <= 7 * 86400 {
                start = s; end = e
            }
            items.append(ItemSuggestion(kind: kind, title: title, body: body, sourceQuote: quote, start: start, end: end))
        }
        return Decoded(items: items, skipped: skipped)
    }
}

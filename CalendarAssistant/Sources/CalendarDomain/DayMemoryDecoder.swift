import Foundation

/// Checks what the local model returned for a day's recordings and turns it into moments. Nothing the model says is
/// trusted: a quote that is not in the transcript, an unknown recording or an impossible time rejects the whole answer.
///
/// The model answers with JSON only:
/// {"moments":[{"recording":"<recording UUID>","offsetSeconds":12,"summary":"…","sourceQuote":"…","importance":60,"tags":["仕事"]}]}
public enum DayMemoryDecoder {
    public static func decode(_ data: Data, recordings: [DayRecording]) throws -> [DayMoment] {
        if data.count > 65_536 { throw InvalidDayMemory() }

        struct RawMoment: Decodable {
            let recording: String
            let offsetSeconds: Double?
            let summary: String
            let sourceQuote: String
            let importance: Int
            let tags: [String]?
        }
        struct RawAnswer: Decodable {
            let moments: [RawMoment]
        }

        let answer: RawAnswer
        do {
            answer = try JSONDecoder().decode(RawAnswer.self, from: data)
        } catch {
            throw InvalidDayMemory()
        }

        if answer.moments.count > 30 { throw InvalidDayMemory() }

        let recordingByID = Dictionary(recordings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var moments: [DayMoment] = []
        for raw in answer.moments {
            guard let recordingID = UUID(uuidString: raw.recording),
                  let recording = recordingByID[recordingID] else {
                throw InvalidDayMemory()
            }

            let summary = raw.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.isEmpty || summary.count > 300 { throw InvalidDayMemory() }

            let sourceQuote = raw.sourceQuote.trimmingCharacters(in: .whitespacesAndNewlines)
            if sourceQuote.isEmpty || !recording.transcript.contains(sourceQuote) {
                throw InvalidDayMemory()
            }

            let offset = raw.offsetSeconds ?? 0
            if offset < 0 || offset > 21_600 { throw InvalidDayMemory() }

            var seen = Set<String>()
            var tags: [String] = []
            for tag in raw.tags ?? [] {
                let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if seen.insert(trimmed).inserted {
                    tags.append(trimmed)
                    if tags.count == 5 { break }
                }
            }

            let importance = min(max(raw.importance, 0), 100)
            let occurredAt = recording.startedAt.addingTimeInterval(offset)

            moments.append(DayMoment(
                id: UUID(),
                occurredAt: occurredAt,
                summary: summary,
                sourceQuote: sourceQuote,
                importance: importance,
                tags: tags,
                recordingID: recordingID,
                userEdited: false
            ))
        }

        return moments.enumerated().sorted { lhs, rhs in
            if lhs.element.occurredAt != rhs.element.occurredAt {
                return lhs.element.occurredAt < rhs.element.occurredAt
            }
            return lhs.offset < rhs.offset
        }.map { $0.element }
    }

    public struct InvalidDayMemory: LocalizedError {
        public init() {}
        public var errorDescription: String? {
            "AIのまとめに、録音と一致しない引用や不正な時刻がありました。保存せずに止めました。もう一度まとめ直せます。"
        }
    }
}

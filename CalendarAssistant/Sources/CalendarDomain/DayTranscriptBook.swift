import Foundation

/// The transcript of one recorded piece (about 10 minutes).
public struct PieceTranscript: Codable, Equatable, Sendable {
    public var start: Date
    public var text: String
    public init(start: Date, text: String) { self.start = start; self.text = text }
}

/// A whole day's transcript, kept piece by piece so a long day can be transcribed in several sittings (2026-10-26).
public struct DayTranscript: Codable, Equatable, Sendable {
    /// Keyed by the piece's chunk ID (`uuidString`).
    public var pieces: [String: PieceTranscript]
    public init(pieces: [String: PieceTranscript] = [:]) { self.pieces = pieces }
}

/// One JSON file per day, `<yyyy-MM-dd>.transcript.json` in `directory`; the date is the day in `calendar`'s time zone.
public struct DayTranscriptBook: Sendable {
    public let directory: URL
    public let calendar: Calendar
    public init(directory: URL, calendar: Calendar) { self.directory = directory; self.calendar = calendar }

    private func fileURL(day: Date) -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return directory.appendingPathComponent(formatter.string(from: day)).appendingPathExtension("transcript.json")
    }

    /// The saved transcript of the day that contains `day`; empty when nothing was saved yet.
    public func load(day: Date) throws -> DayTranscript {
        let url = fileURL(day: day)
        guard FileManager.default.fileExists(atPath: url.path) else { return DayTranscript() }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DayTranscript.self, from: data)
    }

    /// Saves one piece's text (trimmed) and returns the day's transcript.
    @discardableResult
    public func record(_ text: String, piece: UUID, start: Date, day: Date) throws -> DayTranscript {
        var transcript = try load(day: day)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript.pieces[piece.uuidString] = PieceTranscript(start: start, text: trimmed)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(transcript)
        try data.write(to: fileURL(day: day), options: .atomic)
        return transcript
    }

    /// The pieces that have no saved text yet, in the given order.
    public func missing(_ pieces: [UUID], day: Date) throws -> [UUID] {
        let transcript = try load(day: day)
        return pieces.filter { transcript.pieces[$0.uuidString] == nil }
    }

    /// The day's text for reading and for the local model: "[HH:mm] text" per piece, oldest first.
    public static func text(of transcript: DayTranscript, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        let sorted = transcript.pieces.sorted { lhs, rhs in
            if lhs.value.start != rhs.value.start { return lhs.value.start < rhs.value.start }
            return lhs.key < rhs.key
        }
        return sorted
            .filter { !$0.value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "[\(formatter.string(from: $0.value.start))] \($0.value.text)" }
            .joined(separator: "\n")
    }
}

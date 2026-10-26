import Foundation

/// One day of recordings: the Watch saves a piece every 10 minutes, but people think in days (2026-10-26).
public struct RecordingDay<Piece: Sendable>: Sendable {
    /// Start of the day in the calendar's time zone.
    public let day: Date
    /// The day's pieces, oldest first.
    public let pieces: [Piece]
    /// Earliest start and latest end among the pieces.
    public let start: Date
    public let end: Date
    /// Total recorded length: the sum of each piece's length (end - start, never negative).
    public let seconds: TimeInterval

    public init(day: Date, pieces: [Piece], start: Date, end: Date, seconds: TimeInterval) {
        self.day = day; self.pieces = pieces; self.start = start; self.end = end; self.seconds = seconds
    }
}

public enum RecordingDays {
    /// Groups pieces by the calendar day their recording started on; newest day first.
    public static func group<Piece: Sendable>(_ pieces: [Piece], calendar: Calendar,
                                              start: (Piece) -> Date, end: (Piece) -> Date) -> [RecordingDay<Piece>] {
        var buckets: [Date: [Piece]] = [:]
        for piece in pieces {
            let day = calendar.startOfDay(for: start(piece))
            buckets[day, default: []].append(piece)
        }
        return buckets.keys.sorted(by: >).map { day in
            let dayPieces = buckets[day]!
            let sorted = dayPieces.enumerated().sorted { a, b in
                let sa = start(a.element), sb = start(b.element)
                return sa == sb ? a.offset < b.offset : sa < sb
            }.map(\.element)
            let dayStart = sorted.map(start).min()!
            let dayEnd = sorted.map(end).max()!
            let seconds = sorted.reduce(TimeInterval(0)) { $0 + max(0, end($1).timeIntervalSince(start($1))) }
            return RecordingDay(day: day, pieces: sorted, start: dayStart, end: dayEnd, seconds: seconds)
        }
    }
}

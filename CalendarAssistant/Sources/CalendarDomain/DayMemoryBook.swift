import Foundation

/// The Mac's book of days: one JSON file per day (`yyyy-MM-dd.json`, the day in `calendar`'s time zone) in `directory`,
/// holding that day's moments as a JSON array of DayMoment. The user's own edits are never lost to a new summary, and a
/// file that cannot be read is never written over.
public struct DayMemoryBook: Sendable {
    public let directory: URL
    public let calendar: Calendar

    public init(directory: URL, calendar: Calendar) {
        self.directory = directory
        self.calendar = calendar
    }

    /// The moments saved for the day that contains `day`.
    public func load(day: Date) throws -> [DayMoment] {
        let url = fileURL(day: day)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw Failure.unreadable
        }
        do {
            return try JSONDecoder().decode([DayMoment].self, from: data)
        } catch {
            throw Failure.unreadable
        }
    }

    /// Adds a new summary of some recordings to the day and saves it; returns what was saved.
    public func merge(_ new: [DayMoment], day: Date) throws -> [DayMoment] {
        let existing = try load(day: day)
        let newIDs = Set(new.map(\.recordingID))
        let kept = existing.filter { !newIDs.contains($0.recordingID) || $0.userEdited }
        let merged = kept + new
        let sorted = merged.sorted { a, b in
            if a.occurredAt != b.occurredAt { return a.occurredAt < b.occurredAt }
            let aNew = new.contains(where: { $0.id == a.id })
            let bNew = new.contains(where: { $0.id == b.id })
            if aNew != bNew { return !aNew }
            return merged.firstIndex(of: a)! < merged.firstIndex(of: b)!
        }
        try save(sorted, day: day)
        return sorted
    }

    /// Saves the day exactly as given (the user edited or deleted moments by hand).
    public func save(_ moments: [DayMoment], day: Date) throws {
        for moment in moments where !calendar.isDate(moment.occurredAt, inSameDayAs: day) {
            throw Failure.wrongDay
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(moments)
        try data.write(to: fileURL(day: day), options: .atomic)
    }

    private func fileURL(day: Date) -> URL {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return directory.appendingPathComponent(formatter.string(from: day) + ".json")
    }

    public enum Failure: Error, Equatable {
        /// The day's file exists but is not a readable list of moments; nothing was written.
        case unreadable
        /// A moment does not fall on the day being saved.
        case wrongDay
    }
}

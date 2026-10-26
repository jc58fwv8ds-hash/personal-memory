import Foundation

/// The day's suggestions and what the user did with them, `<yyyy-MM-dd>.suggestions.json` in `directory` (the day in
/// `calendar`'s time zone). Asking the model again must not bring back what the user dismissed or saved (2026-10-26).
public struct DaySuggestionBook: Sendable {
    public let directory: URL
    public let calendar: Calendar
    public init(directory: URL, calendar: Calendar) { self.directory = directory; self.calendar = calendar }

    public struct NotFound: Error, Equatable { public init() {} }

    private func fileURL(day: Date) -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return directory.appendingPathComponent("\(formatter.string(from: day)).suggestions.json")
    }

    private func save(_ items: [ItemSuggestion], day: Date) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(items)
        try data.write(to: fileURL(day: day), options: .atomic)
    }

    /// The saved suggestions of the day that contains `day`, in saved order; empty when none.
    public func load(day: Date) throws -> [ItemSuggestion] {
        let url = fileURL(day: day)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ItemSuggestion].self, from: data)
    }

    /// Adds new suggestions after the saved ones and saves; returns the day's list.
    @discardableResult
    public func merge(_ new: [ItemSuggestion], day: Date) throws -> [ItemSuggestion] {
        var items = try load(day: day)
        for item in new {
            if items.contains(where: { $0.kind == item.kind && $0.sourceQuote == item.sourceQuote }) { continue }
            items.append(item)
        }
        try save(items, day: day)
        return items
    }

    /// Replaces the saved suggestion with the same id and saves; returns the day's list.
    @discardableResult
    public func update(_ item: ItemSuggestion, day: Date) throws -> [ItemSuggestion] {
        var items = try load(day: day)
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { throw NotFound() }
        items[index] = item
        try save(items, day: day)
        return items
    }
}

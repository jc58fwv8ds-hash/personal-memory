import Foundation

/// No EventKit, Speech, transport or UI dependencies. Model output is only a draft.
public struct CalendarProposal: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var sourceQuote: String
    public var start: Date?
    public var end: Date?
    public var notes: String
    public var dateConfirmed: Bool
    public init(id: UUID = UUID(), title: String, sourceQuote: String, start: Date? = nil,
                end: Date? = nil, notes: String = "", dateConfirmed: Bool = false) {
        self.id = id; self.title = title; self.sourceQuote = sourceQuote
        self.start = start; self.end = end; self.notes = notes; self.dateConfirmed = dateConfirmed
    }
    public var canRegister: Bool {
        guard dateConfirmed, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 200, notes.count <= 4000, let start, let end else { return false }
        return start.timeIntervalSince1970.isFinite && end.timeIntervalSince1970.isFinite
            && end > start && end.timeIntervalSince(start) <= 7 * 86400
    }
}

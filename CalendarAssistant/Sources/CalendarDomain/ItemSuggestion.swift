import Foundation

/// One thing from the day's recording the local model suggests keeping: a calendar event or a memo (2026-10-26).
/// Only a draft: nothing is saved until the user confirms it.
public struct ItemSuggestion: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case calendar, memo }
    public enum State: String, Codable, Sendable {
        case suggested
        /// Written before saving to Calendar or Notes: if the app stops here the outcome is unknown and is not retried.
        case saving
        case saved, dismissed
    }
    public var id: UUID
    public var kind: Kind
    public var title: String
    public var body: String
    /// Exact words from the transcript the suggestion is based on.
    public var sourceQuote: String
    /// Calendar suggestions only; nil when the recording did not say when.
    public var start: Date?
    public var end: Date?
    public var state: State

    public init(id: UUID = UUID(), kind: Kind, title: String, body: String, sourceQuote: String,
                start: Date? = nil, end: Date? = nil, state: State = .suggested) {
        self.id = id; self.kind = kind; self.title = title; self.body = body; self.sourceQuote = sourceQuote
        self.start = start; self.end = end; self.state = state
    }
}

import Foundation

/// One moment of the day, drawn from a recording. Model output is only a draft until the user reviews it.
public struct DayMoment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var occurredAt: Date
    public var summary: String
    /// Exact words from the recording's transcript that the summary is based on.
    public var sourceQuote: String
    /// 0...100
    public var importance: Int
    public var tags: [String]
    public var recordingID: UUID
    /// The user changed this moment by hand; a new summary of the same recording must not replace it.
    public var userEdited: Bool

    public init(id: UUID = UUID(), occurredAt: Date, summary: String, sourceQuote: String, importance: Int,
                tags: [String], recordingID: UUID, userEdited: Bool = false) {
        self.id = id; self.occurredAt = occurredAt; self.summary = summary; self.sourceQuote = sourceQuote
        self.importance = importance; self.tags = tags; self.recordingID = recordingID; self.userEdited = userEdited
    }
}

/// A transcribed recording of the day.
public struct DayRecording: Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let transcript: String
    public init(id: UUID, startedAt: Date, transcript: String) {
        self.id = id; self.startedAt = startedAt; self.transcript = transcript
    }
}

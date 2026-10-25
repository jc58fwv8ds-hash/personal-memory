import Foundation

public struct MemoryEvent: Codable, Equatable, Sendable {
    public let id: UUID
    public let occurredAt: Date
    public let transcript: String
    public let importance: Int
    public let tags: [String]
    public let sourceCaptureIDs: [UUID]

    public init(
        id: UUID,
        occurredAt: Date,
        transcript: String,
        importance: Int,
        tags: [String],
        sourceCaptureIDs: [UUID]
    ) {
        self.id = id
        self.occurredAt = occurredAt
        
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transcript = trimmedTranscript.isEmpty ? "" : trimmedTranscript
        
        self.importance = min(max(importance, 0), 100)
        
        var seenTags = Set<String>()
        let cleanedTags: [String] = tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !seenTags.contains(trimmed) {
                seenTags.insert(trimmed)
                return trimmed
            }
            return nil
        }.prefix(12).map { $0 }
        self.tags = Array(cleanedTags)
        
        var seenIDs = Set<UUID>()
        let uniqueCaptureIDs: [UUID] = sourceCaptureIDs.compactMap { captureID in
            if !seenIDs.contains(captureID) {
                seenIDs.insert(captureID)
                return captureID
            }
            return nil
        }
        self.sourceCaptureIDs = uniqueCaptureIDs
    }
}
import Foundation

/// Value state only. The recorder commits audio and metadata before calling finalize.
public struct RecordingSession: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case recording, paused, interrupted, ended }
    public enum Boundary: String, Codable, Sendable {
        case rollover, privacyPause, interruption, battery, storage, termination, stop
    }
    public struct Chunk: Codable, Equatable, Sendable {
        public let sessionID: UUID
        public let chunkID: UUID
        public let sequence: Int
        public let start: Date
        public let end: Date
        public let duration: TimeInterval
        public let checksum: String
        public let localState: String
        public let transferState: String
        public let boundary: Boundary
    }
    public enum Failure: Error { case invalidTransition, invalidMetadata, duplicateChunk }
    public let schemaVersion: Int
    public let sessionID: UUID
    public let startedAt: Date
    public private(set) var phase: Phase = .recording
    public private(set) var chunkStartedAt: Date
    public private(set) var chunks: [Chunk] = []
    public private(set) var resumeAfter: Date?

    public init(id: UUID = UUID(), start: Date) {
        schemaVersion = 1
        sessionID = id; startedAt = start; chunkStartedAt = start
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, sessionID, startedAt, phase, chunkStartedAt, chunks, resumeAfter
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        sessionID = try values.decode(UUID.self, forKey: .sessionID)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        phase = try values.decode(Phase.self, forKey: .phase)
        chunkStartedAt = try values.decode(Date.self, forKey: .chunkStartedAt)
        chunks = try values.decode([Chunk].self, forKey: .chunks)
        resumeAfter = try values.decodeIfPresent(Date.self, forKey: .resumeAfter)
        guard isValidPersistedState else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid recording session state"))
        }
    }

    private var isValidPersistedState: Bool {
        guard schemaVersion == 1, chunkStartedAt >= startedAt,
              resumeAfter == nil || (phase == .paused && resumeAfter! > chunkStartedAt),
              phase != .ended || !chunks.isEmpty || chunkStartedAt == startedAt else { return false }
        var previousEnd = startedAt
        var identifiers = Set<UUID>()
        for (index, chunk) in chunks.enumerated() {
            guard chunk.sessionID == sessionID, chunk.sequence == index + 1,
                  identifiers.insert(chunk.chunkID).inserted,
                  chunk.start >= previousEnd, chunk.end >= chunk.start,
                  chunk.duration.isFinite, chunk.duration > 0,
                  chunk.duration <= chunk.end.timeIntervalSince(chunk.start) + 1,
                  chunk.checksum.count == 64,
                  chunk.checksum.allSatisfy({ "0123456789abcdef".contains($0) }),
                  chunk.localState == "committed", chunk.transferState == "pending",
                  index == chunks.count - 1 || chunk.boundary != .stop else { return false }
            previousEnd = chunk.end
        }
        guard chunkStartedAt >= previousEnd else { return false }
        if let last = chunks.last {
            if last.boundary == .stop { return phase == .ended }
            if phase == .ended { return last.boundary == .privacyPause || last.boundary == .interruption ||
                last.boundary == .battery || last.boundary == .storage || last.boundary == .termination }
        }
        return true
    }

    public mutating func finalizeCommittedChunk(id: UUID, end: Date, duration: TimeInterval,
                                                checksum: String, boundary: Boundary,
                                                automaticResumeAfter: Date? = nil) throws {
        guard phase == .recording else { throw Failure.invalidTransition }
        guard end >= chunkStartedAt, duration.isFinite, duration > 0,
              duration <= end.timeIntervalSince(chunkStartedAt) + 1,
              checksum.count == 64, checksum.allSatisfy({ "0123456789abcdef".contains($0) }),
              automaticResumeAfter == nil || (boundary == .privacyPause && automaticResumeAfter! > end)
        else { throw Failure.invalidMetadata }
        guard !chunks.contains(where: { $0.chunkID == id }) else { throw Failure.duplicateChunk }
        chunks.append(Chunk(sessionID: sessionID, chunkID: id, sequence: chunks.count + 1,
            start: chunkStartedAt, end: end, duration: duration, checksum: checksum,
            localState: "committed", transferState: "pending", boundary: boundary))
        chunkStartedAt = end
        resumeAfter = automaticResumeAfter
        switch boundary {
        case .rollover: break
        case .privacyPause: phase = .paused
        case .stop: phase = .ended
        default: phase = .interrupted
        }
    }

    public mutating func resume(at date: Date) throws {
        guard phase == .paused || phase == .interrupted, date >= chunkStartedAt else {
            throw Failure.invalidTransition
        }
        chunkStartedAt = date; resumeAfter = nil; phase = .recording
    }

    public mutating func stopWithoutActiveAudio() throws {
        guard phase == .paused || phase == .interrupted else { throw Failure.invalidTransition }
        phase = .ended; resumeAfter = nil
    }

    /// A persisted recording flag does not establish that hardware is still recording.
    public mutating func reconcileAfterRestart() {
        if phase == .recording { phase = .interrupted }
        resumeAfter = nil
    }
}

public struct RecordingChunkPolicy: Codable, Equatable, Sendable {
    public let targetDuration: TimeInterval
    public init(targetDuration: TimeInterval = 600) throws {
        guard targetDuration.isFinite, (300...900).contains(targetDuration) else {
            throw RecordingSession.Failure.invalidMetadata
        }
        self.targetDuration = targetDuration
    }
    public func shouldFinalize(elapsed: TimeInterval, pressure: Bool) -> Bool {
        pressure || elapsed >= targetDuration
    }
}

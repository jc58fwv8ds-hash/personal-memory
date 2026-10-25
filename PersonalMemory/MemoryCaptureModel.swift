import Foundation

public enum CaptureDevice: String, Equatable, Sendable {
    case appleWatch
    case iPhone
    case mac
    case unknown
}

extension CaptureDevice: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = CaptureDevice(rawValue: rawValue) ?? .unknown
    }
}

public enum CaptureState: String, Equatable, Sendable {
    case captured
    case queued
    case transferred
    case failed
    case unknown
}

extension CaptureState: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = CaptureState(rawValue: rawValue) ?? .unknown
    }
}

public struct MemoryCapture: Codable, Equatable, Sendable {
    public let id: UUID
    public let localAudioReference: String
    public let capturedAt: Date
    public let device: CaptureDevice
    public let durationSeconds: Double
    public let state: CaptureState

    public init(
        id: UUID,
        localAudioReference: String,
        capturedAt: Date,
        device: CaptureDevice,
        durationSeconds: Double,
        state: CaptureState
    ) {
        self.id = id
        self.localAudioReference = localAudioReference.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.capturedAt = capturedAt
        self.device = device
        self.durationSeconds = durationSeconds.isFinite && durationSeconds > 0
            ? durationSeconds
            : 0
        self.state = state
    }
}

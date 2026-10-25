import Foundation

/// Durable session metadata. Audio is committed separately before a chunk is appended.
public struct RecordingSessionStore: Sendable {
    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func save(_ session: RecordingSession) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = url(for: session.sessionID)
        let data = try JSONEncoder().encode(session)
        // Decode through the validation boundary before publishing the new snapshot.
        _ = try JSONDecoder().decode(RecordingSession.self, from: data)
        try data.write(to: destination, options: .atomic)
    }

    public func load(id: UUID) throws -> RecordingSession? {
        let destination = url(for: id)
        guard FileManager.default.fileExists(atPath: destination.path) else { return nil }
        let session = try JSONDecoder().decode(RecordingSession.self,
            from: Data(contentsOf: destination))
        guard session.sessionID == id else { throw CocoaError(.fileReadCorruptFile) }
        return session
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".json", isDirectory: false)
    }
}

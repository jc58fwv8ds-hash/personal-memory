import Foundation
import Testing
@testable import SessionDomain

struct RecordingSessionTests {
    let hash = String(repeating: "a", count: 64)
    @Test func workDayRemainsOneSessionWithImmutableChunks() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var session = RecordingSession(start: start)
        for index in 1...48 {
            try session.finalizeCommittedChunk(id: UUID(), end: start.addingTimeInterval(Double(index) * 600),
                duration: 600, checksum: hash, boundary: index == 48 ? .stop : .rollover)
        }
        #expect(session.phase == .ended)
        #expect(session.chunks.count == 48)
        #expect(Set(session.chunks.map(\.sessionID)).count == 1)
        #expect(session.chunks.last?.sequence == 48)
    }
    @Test func privacyPauseExcludesPausedTimeAndRestartDoesNotResumeMicrophone() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var session = RecordingSession(start: start)
        try session.finalizeCommittedChunk(id: UUID(), end: start.addingTimeInterval(20), duration: 20,
            checksum: hash, boundary: .privacyPause, automaticResumeAfter: start.addingTimeInterval(320))
        #expect(throws: RecordingSession.Failure.self) {
            try session.finalizeCommittedChunk(id: UUID(), end: start.addingTimeInterval(40), duration: 20,
                checksum: hash, boundary: .rollover)
        }
        try session.resume(at: start.addingTimeInterval(320))
        #expect(session.chunkStartedAt == start.addingTimeInterval(320))
        let bytes = try JSONEncoder().encode(session)
        var restored = try JSONDecoder().decode(RecordingSession.self, from: bytes)
        restored.reconcileAfterRestart()
        #expect(restored.phase == .interrupted)
        #expect(restored.chunks == session.chunks)
    }
    @Test func invalidMetadataDoesNotAdvanceSequence() throws {
        var session = RecordingSession(start: .now)
        #expect(throws: RecordingSession.Failure.self) {
            try session.finalizeCommittedChunk(id: UUID(), end: .now, duration: 1,
                checksum: "invalid", boundary: .stop)
        }
        #expect(session.chunks.isEmpty)
        #expect(session.phase == .recording)
        #expect(throws: RecordingSession.Failure.self) { try RecordingChunkPolicy(targetDuration: .nan) }
        #expect(try RecordingChunkPolicy(targetDuration: 900).shouldFinalize(elapsed: 10, pressure: true))
    }

    @Test func restoredSessionRejectsUnsupportedSchemaAndBrokenSequence() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var session = RecordingSession(start: start)
        try session.finalizeCommittedChunk(id: UUID(), end: start.addingTimeInterval(20),
            duration: 20, checksum: hash, boundary: .rollover)
        let data = try JSONEncoder().encode(session)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 2
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RecordingSession.self, from: JSONSerialization.data(withJSONObject: object))
        }
        object["schemaVersion"] = 1
        var chunks = try #require(object["chunks"] as? [[String: Any]])
        chunks[0]["sequence"] = 2
        object["chunks"] = chunks
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RecordingSession.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func sessionStoreRestoresCommittedMetadataAndRejectsMismatchedIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingSessionStore(directory: directory)
        let start = Date(timeIntervalSince1970: 1000)
        var session = RecordingSession(start: start)
        #expect(try store.load(id: session.sessionID) == nil)
        try session.finalizeCommittedChunk(id: UUID(), end: start.addingTimeInterval(30),
            duration: 30, checksum: hash, boundary: .privacyPause)
        try store.save(session)
        #expect(try store.load(id: session.sessionID) == session)
        let renamed = directory.appendingPathComponent(UUID().uuidString + ".json")
        try FileManager.default.copyItem(at: directory.appendingPathComponent(session.sessionID.uuidString + ".json"), to: renamed)
        let wrongID = try #require(UUID(uuidString: renamed.deletingPathExtension().lastPathComponent))
        #expect(throws: CocoaError.self) { try store.load(id: wrongID) }
    }
}

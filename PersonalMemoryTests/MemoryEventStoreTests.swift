import Foundation
import Testing
@testable import PersonalMemory

struct MemoryEventStoreTests {
    @Test func reopenPreservesNotesAndSavingAgainKeepsBoth() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("nested/events.json")
        let first = MemoryEvent(id: UUID(), occurredAt: Date(timeIntervalSince1970: 10), transcript: "散歩した 🌸", importance: 50, tags: [], sourceCaptureIDs: [])
        let second = MemoryEvent(id: UUID(), occurredAt: Date(timeIntervalSince1970: 20), transcript: "コーヒーを飲んだ ☕️", importance: 50, tags: [], sourceCaptureIDs: [])
        let store = MemoryEventStore(fileURL: url)
        #expect(try store.load().isEmpty)
        try store.save([first])
        let reopened = MemoryEventStore(fileURL: url)
        #expect(try reopened.load() == [first])
        try reopened.save(try reopened.load() + [second])
        #expect(try MemoryEventStore(fileURL: url).load() == [first, second])
    }

    @Test func corruptedDataCannotBeSilentlyOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("events.json")
        let damaged = Data("not valid JSON".utf8)
        try damaged.write(to: url)
        let store = MemoryEventStore(fileURL: url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(throws: (any Error).self) { try store.save([]) }
        #expect(try Data(contentsOf: url) == damaged)
    }

    @Test func invalidDestinationFailsWithoutTouchingOtherFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blocked = root.appendingPathComponent("blocked")
        try Data("keep".utf8).write(to: blocked)
        let store = MemoryEventStore(fileURL: blocked.appendingPathComponent("events.json"))
        #expect(throws: (any Error).self) { try store.save([]) }
        #expect(try String(contentsOf: blocked, encoding: .utf8) == "keep")
    }
}

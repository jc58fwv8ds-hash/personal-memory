import Foundation
import Testing
import CryptoKit
@testable import PersonalMemory
import SessionDomain

struct CaptureAudioInboxTests {
    @Test func inventoryIgnoresIncompleteFilesAndRejectsInvalidDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = CaptureAudioInbox(directory: root)
        #expect(try inbox.recordings().isEmpty)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["unknown.m4a", "\(UUID().uuidString).tmp", "\(UUID().uuidString).pending.m4a"] {
            try Data([1]).write(to: root.appendingPathComponent(name))
        }
        #expect(try inbox.recordings().isEmpty)
        let notDirectory = root.appendingPathComponent("unknown.m4a")
        #expect(throws: (any Error).self) { try CaptureAudioInbox(directory: notDirectory).recordings() }
    }

    @Test func temporarySourceCanDisappearAfterReceiptAndDuplicateIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let input = root.appendingPathComponent("incoming")
        let payload = Data([1, 2, 3, 4])
        try payload.write(to: input)
        let inbox = CaptureAudioInbox(directory: root.appendingPathComponent("inbox"))
        let id = UUID()
        let saved = try inbox.receive(fileURL: input, id: id)
        #expect(try inbox.receive(fileURL: input, id: id) == saved)
        #expect(try inbox.recordings().count == 1)
        try FileManager.default.removeItem(at: input)
        #expect(try Data(contentsOf: saved) == payload)
        let reloaded = try CaptureAudioInbox(directory: root.appendingPathComponent("inbox")).recordings()
        #expect(reloaded.map(\.standardizedFileURL.path) == [saved.standardizedFileURL.path])
    }

    @Test func conflictingOrInvalidInputDoesNotDestroyOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let input = root.appendingPathComponent("incoming")
        try Data([1]).write(to: input)
        let inbox = CaptureAudioInbox(directory: root.appendingPathComponent("inbox"))
        let id = UUID()
        let saved = try inbox.receive(fileURL: input, id: id)
        try Data([2]).write(to: input)
        #expect(throws: (any Error).self) { try inbox.receive(fileURL: input, id: id) }
        #expect(try Data(contentsOf: saved) == Data([1]))
        try Data().write(to: input)
        #expect(throws: (any Error).self) { try inbox.receive(fileURL: input, id: UUID()) }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: saved)
        #expect(throws: (any Error).self) { try inbox.receive(fileURL: link, id: UUID()) }
        #expect(try inbox.recordings().count == 1)
    }

    @Test func sessionChunkReceiptVerifiesChecksumAndSurvivesDuplicateDelivery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("incoming.m4a")
        let payload = Data([1, 2, 3, 4])
        try payload.write(to: source)
        let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let start = Date(timeIntervalSince1970: 1000)
        var session = RecordingSession(start: start)
        try session.finalizeCommittedChunk(id: UUID(), end: start.addingTimeInterval(10),
            duration: 10, checksum: hash, boundary: .rollover)
        let chunk = try #require(session.chunks.first)
        let inbox = SessionChunkInbox(directory: root.appendingPathComponent("inbox"))
        let saved = try inbox.receive(fileURL: source, chunk: chunk)
        #expect(try inbox.receive(fileURL: source, chunk: chunk) == saved)
        #expect(try inbox.receiptCount() == 1)
        let metadata = saved.deletingPathExtension().appendingPathExtension("json")
        try FileManager.default.removeItem(at: metadata)
        #expect(try inbox.receiptCount() == 0)
        #expect(try inbox.receive(fileURL: source, chunk: chunk) == saved)
        #expect(try inbox.receiptCount() == 1)
        #expect(try Data(contentsOf: saved) == payload)
        try Data([9]).write(to: source)
        #expect(throws: (any Error).self) { try inbox.receive(fileURL: source, chunk: chunk) }
        #expect(try Data(contentsOf: saved) == payload)
    }
}

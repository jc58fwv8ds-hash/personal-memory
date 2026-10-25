import Foundation
import Testing
@testable import CalendarDomain

struct RecordingWorkspaceTests {
    @Test func repeatImportPreservesDraftAndUncertainSubmission() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("fixture.m4a")
        let bytes = Data("synthetic-storage-fixture-not-real-audio".utf8)
        try bytes.write(to: source)
        let workspace = RecordingWorkspace(root: directory.appendingPathComponent("inbox"))
        var first = try workspace.importRecording(source)
        first.transcript = "明日歯医者"
        let id = UUID(); first.submissions[id] = "uncertain"
        try workspace.save(first)
        let second = try workspace.importRecording(source)
        #expect(second.recordingHash == first.recordingHash)
        #expect(second.transcript == first.transcript)
        #expect(second.submissions[id] == "uncertain")
        #expect(try Data(contentsOf: source) == bytes)
        #expect(try Data(contentsOf: workspace.audioURL(first.recordingHash)) == bytes)
    }
    @Test func corruptDraftDoesNotResetRegistrationState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("fixture.m4a")
        try Data([1, 2, 3]).write(to: source)
        let workspace = RecordingWorkspace(root: directory.appendingPathComponent("inbox"))
        let first = try workspace.importRecording(source)
        try Data("broken".utf8).write(to: workspace.root.appendingPathComponent(first.recordingHash + ".json"))
        #expect(throws: (any Error).self) { try workspace.importRecording(source) }
    }
    @Test func invalidAudioAndPathAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = RecordingWorkspace(root: directory.appendingPathComponent("inbox"))
        let source = directory.appendingPathComponent("empty.m4a")
        try Data().write(to: source)
        #expect(throws: (any Error).self) { try workspace.importRecording(source) }
        #expect(throws: (any Error).self) { try workspace.audioURL("../../bad") }
        try Data([1]).write(to: source)
        let link = directory.appendingPathComponent("link.m4a")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        #expect(throws: (any Error).self) { try workspace.importRecording(link) }
    }
    @Test func invalidEditedDates() {
        var draft = CalendarProposal(title: "予定", sourceQuote: "予定", start: Date(), end: Date().addingTimeInterval(-1), dateConfirmed: true)
        #expect(!draft.canRegister)
        draft.end = nil
        #expect(!draft.canRegister)
    }
}

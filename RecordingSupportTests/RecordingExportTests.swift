import Foundation
import Testing
@testable import RecordingSupport

struct RecordingExportTests {
    @Test func sharesACopyWithoutChangingOriginalOrOverwritingAnExport() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("\(UUID()).m4a")
        let payload = Data([1, 2, 3, 4])
        try payload.write(to: source)
        let output = try RecordingExport.prepare(recording: source, in: root.appendingPathComponent("exports"))
        #expect(output.deletingLastPathComponent() == root.appendingPathComponent("exports"))
        #expect(output.lastPathComponent == source.lastPathComponent)
        #expect(try Data(contentsOf: output) == payload)
        #expect(try Data(contentsOf: source) == payload)
        #expect(throws: (any Error).self) {
            try RecordingExport.prepare(recording: source, in: root.appendingPathComponent("exports"))
        }
        #expect(try Data(contentsOf: output) == payload)
    }

    @Test(arguments: ["empty", "oversized", "name", "link", "directory", "missing"])
    func rejectsInvalidSources(kind: String) throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent(kind == "name" ? "unknown.m4a" : "\(UUID()).m4a")
        let fm = FileManager.default
        switch kind {
        case "missing": break
        case "directory": try fm.createDirectory(at: source, withIntermediateDirectories: false)
        case "link":
            let real = root.appendingPathComponent("original")
            try Data([9]).write(to: real)
            try fm.createSymbolicLink(at: source, withDestinationURL: real)
        default:
            try Data(kind == "empty" ? [] : [9]).write(to: source)
            if kind == "oversized" {
                let handle = try FileHandle(forWritingTo: source)
                try handle.truncate(atOffset: 20_000_001)
                try handle.close()
            }
        }
        #expect(throws: (any Error).self) {
            try RecordingExport.prepare(recording: source, in: root.appendingPathComponent("exports"))
        }
    }

    @Test func refusesLinkedDestination() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("\(UUID()).m4a")
        try Data([1]).write(to: source)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("exports"))
        #expect(throws: (any Error).self) { try RecordingExport.prepare(recording: source, in: link) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("exports").path).isEmpty)
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingExportTest-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("exports"), withIntermediateDirectories: true)
        return root
    }
}

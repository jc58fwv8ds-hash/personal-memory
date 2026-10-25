import Foundation
import Testing
@testable import RecordingSupport

struct RecordingCatalogTests {
    @Test func listsOnlyFinalRegularAudioInStableNewestOrderWithoutChangingFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let older = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let newer = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let tied = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        for (id, time) in [(older, 100.0), (newer, 200.0), (tied, 200.0)] {
            let url = root.appendingPathComponent("\(id).m4a")
            try Data([1, 2, 3]).write(to: url)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: time)], ofItemAtPath: url.path)
        }
        for name in ["unknown.m4a", "\(UUID()).pending.m4a", "\(UUID()).tmp"] {
            try Data([1]).write(to: root.appendingPathComponent(name))
        }
        try Data().write(to: root.appendingPathComponent("\(UUID()).m4a"))
        let oversized = root.appendingPathComponent("\(UUID()).m4a")
        #expect(fm.createFile(atPath: oversized.path, contents: nil))
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: 20_000_001)
        try handle.close()
        let source = root.appendingPathComponent("\(older).m4a")
        try fm.createSymbolicLink(at: root.appendingPathComponent("\(UUID()).m4a"), withDestinationURL: source)
        try fm.createDirectory(at: root.appendingPathComponent("\(UUID()).m4a"), withIntermediateDirectories: true)
        let before = try fm.contentsOfDirectory(atPath: root.path).sorted()
        let items = try RecordingCatalog.recordings(in: root)
        #expect(items.map(\.id) == [newer, tied, older])
        #expect(items.allSatisfy { $0.byteCount == 3 })
        #expect(try Data(contentsOf: source) == Data([1, 2, 3]))
        #expect(try fm.contentsOfDirectory(atPath: root.path).sorted() == before)
    }

    @Test func missingIsEmptyButInvalidOrLinkedRootIsAnError() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        #expect(try RecordingCatalog.recordings(in: root.appendingPathComponent("missing")).isEmpty)
        let invalid = root.appendingPathComponent("file")
        try Data([1]).write(to: invalid)
        #expect(throws: (any Error).self) { try RecordingCatalog.recordings(in: invalid) }
        let linked = root.appendingPathComponent("link")
        try fm.createSymbolicLink(at: linked, withDestinationURL: root)
        #expect(throws: (any Error).self) { try RecordingCatalog.recordings(in: linked) }
        let dangling = root.appendingPathComponent("dangling")
        try fm.createSymbolicLink(atPath: dangling.path, withDestinationPath: root.appendingPathComponent("missing").path)
        #expect(throws: (any Error).self) { try RecordingCatalog.recordings(in: dangling) }
    }

    @Test func receivedSessionChunksAppearOnlyAfterManifestCommit() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let session = root.appendingPathComponent("Sessions/\(UUID().uuidString)")
        try fm.createDirectory(at: session, withIntermediateDirectories: true)
        let id = UUID()
        let audio = session.appendingPathComponent(id.uuidString + ".m4a")
        try Data([1, 2, 3]).write(to: audio)
        #expect(try RecordingCatalog.recordings(in: root).isEmpty)
        try Data([4]).write(to: session.appendingPathComponent(id.uuidString + ".json"))
        let items = try RecordingCatalog.recordings(in: root)
        #expect(items.count == 1)
        #expect(items.first?.url.resolvingSymlinksInPath() == audio.resolvingSymlinksInPath())
    }
}

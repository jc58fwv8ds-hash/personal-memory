import Foundation

/// The folder iPhone and Mac share (the user picks it once on each, e.g. iCloud Drive/Personal Memory). Each recording
/// piece is one `<chunkID>.pmchunk` file (ChunkTransferBundle: metadata and audio together, checked by SHA-256 when it is
/// unpacked), so a half-synced pair of files can never be mistaken for a finished recording.
public enum RelayFolder {
    public struct Scan: Equatable, Sendable {
        public var ready: [URL]
        public var notDownloaded: [URL]
        public init(ready: [URL] = [], notDownloaded: [URL] = []) { self.ready = ready; self.notDownloaded = notDownloaded }
    }

    public static func deposit(audio: URL, chunk: RecordingSession.Chunk, into folder: URL) throws -> URL {
        let target = folder.appendingPathComponent(chunk.chunkID.uuidString + ".pmchunk")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory), !isDirectory.boolValue { return target }
        try ChunkTransferBundle.pack(audio: audio, chunk: chunk, destination: target)
        return target
    }

    public static func scan(_ folder: URL, imported: Set<UUID>) throws -> Scan {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return Scan() }
        var ready: [String: URL] = [:], placeholders: [UUID: URL] = [:], present = Set<UUID>()
        for name in try fm.contentsOfDirectory(atPath: folder.path) {
            let url = folder.appendingPathComponent(name)
            guard (try? fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular else { continue }
            if name.hasSuffix(".pmchunk"), let id = UUID(uuidString: String(name.dropLast(8))) {
                present.insert(id)
                if !imported.contains(id) { ready[name] = url }
            } else if name.hasPrefix("."), name.hasSuffix(".pmchunk.icloud"),
                      let id = UUID(uuidString: String(name.dropFirst().dropLast(15))) {
                placeholders[id] = url
            }
        }
        let waiting = placeholders.filter { !imported.contains($0.key) && !present.contains($0.key) }.map(\.value)
        return Scan(ready: ready.keys.sorted().map { ready[$0]! },
                    notDownloaded: waiting.sorted { $0.lastPathComponent < $1.lastPathComponent })
    }
}

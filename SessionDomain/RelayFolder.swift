import Foundation

/// The folder iPhone and Mac share (the user picks it once on each, e.g. iCloud Drive/Personal Memory). Each recording
/// piece is one `<chunkID>.pmchunk` file (ChunkTransferBundle: metadata and audio together, checked by SHA-256 when it is
/// unpacked), so a half-synced pair of files can never be mistaken for a finished recording.
public enum RelayFolder {
    public struct Scan: Equatable, Sendable {
        /// `<UUID>.pmchunk` files that are on this Mac and not imported yet, sorted by file name.
        public var ready: [URL]
        /// iCloud placeholders (`.<UUID>.pmchunk.icloud`) of pieces not imported yet and not on this Mac yet, sorted by file name.
        public var notDownloaded: [URL]
        public init(ready: [URL] = [], notDownloaded: [URL] = []) { self.ready = ready; self.notDownloaded = notDownloaded }
    }

    /// Puts one received piece into the folder as `<chunkID>.pmchunk`; returns that file.
    public static func deposit(audio: URL, chunk: RecordingSession.Chunk, into folder: URL) throws -> URL {
        let destination = folder.appendingPathComponent(chunk.chunkID.uuidString + ".pmchunk", isDirectory: false)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            return destination
        }
        try ChunkTransferBundle.pack(audio: audio, chunk: chunk, destination: destination)
        return destination
    }

    /// What can be imported now, and what is still only in the cloud.
    public static func scan(_ folder: URL, imported: Set<UUID>) throws -> Scan {
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.path) else { return Scan() }
        let entries = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        var ready: [URL] = []
        var placeholders: [(id: UUID, url: URL)] = []
        var presentChunks: Set<UUID> = []
        for entry in entries {
            let name = entry.lastPathComponent
            guard let values = try? entry.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else { continue }
            if name.hasSuffix(".pending") { continue }
            if name.hasSuffix(".pmchunk"), let id = UUID(uuidString: String(name.dropLast(".pmchunk".count))) {
                presentChunks.insert(id)
                if !imported.contains(id) { ready.append(entry) }
            } else if name.hasSuffix(".pmchunk.icloud"), name.hasPrefix("."),
                      let id = UUID(uuidString: String(name.dropFirst().dropLast(".pmchunk.icloud".count))) {
                placeholders.append((id, entry))
            }
        }
        // Filtered after the loop: the directory order is not defined, so a placeholder may be listed before its file.
        let notDownloaded = placeholders.filter { !imported.contains($0.id) && !presentChunks.contains($0.id) }.map(\.url)
        return Scan(ready: ready.sorted { $0.lastPathComponent < $1.lastPathComponent },
                    notDownloaded: notDownloaded.sorted { $0.lastPathComponent < $1.lastPathComponent })
    }
}

import Foundation
import CryptoKit
#if canImport(SessionDomain)
import SessionDomain
#endif

/// iPhone's durable receipt for one immutable Watch recording chunk.
public struct SessionChunkInbox: Sendable {
    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func receiptCount() throws -> Int {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return 0 }
        let sessions = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        var count = 0
        for session in sessions where UUID(uuidString: session.lastPathComponent) != nil {
            guard (try session.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { continue }
            let files = try manager.contentsOfDirectory(at: session, includingPropertiesForKeys: nil)
            for metadata in files where metadata.pathExtension == "json" {
                guard let id = UUID(uuidString: metadata.deletingPathExtension().lastPathComponent) else { continue }
                let audio = session.appendingPathComponent(id.uuidString + ".m4a")
                if manager.fileExists(atPath: audio.path) { count += 1 }
            }
        }
        return count
    }

    /// Every saved piece with its metadata, oldest first (what the shared-folder relay sends to the Mac).
    public func pieces() throws -> [(audio: URL, chunk: RecordingSession.Chunk)] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return [] }
        var found: [(audio: URL, chunk: RecordingSession.Chunk)] = []
        for session in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        where UUID(uuidString: session.lastPathComponent) != nil {
            guard (try session.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { continue }
            for metadata in try manager.contentsOfDirectory(at: session, includingPropertiesForKeys: nil)
            where metadata.pathExtension == "json" {
                guard let id = UUID(uuidString: metadata.deletingPathExtension().lastPathComponent),
                      let chunk = try? JSONDecoder().decode(RecordingSession.Chunk.self, from: Data(contentsOf: metadata)),
                      chunk.chunkID == id else { continue }
                let audio = session.appendingPathComponent(id.uuidString + ".m4a")
                if manager.fileExists(atPath: audio.path) { found.append((audio, chunk)) }
            }
        }
        return found.sorted { $0.chunk.start < $1.chunk.start }
    }

    /// Deletes the audio of these pieces from this iPhone after the user deleted them on the Mac (2026-10-27).
    /// The piece's record (`<chunkID>.json`) stays. Returns how many audio files were deleted.
    @discardableResult
    public func removeAudio(of chunkIDs: Set<UUID>) throws -> Int {
        let manager = FileManager.default
        guard !chunkIDs.isEmpty, manager.fileExists(atPath: directory.path) else { return 0 }
        var removed = 0
        for session in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        where UUID(uuidString: session.lastPathComponent) != nil {
            guard (try session.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { continue }
            for metadata in try manager.contentsOfDirectory(at: session, includingPropertiesForKeys: nil)
            where metadata.pathExtension == "json" {
                guard let id = UUID(uuidString: metadata.deletingPathExtension().lastPathComponent),
                      chunkIDs.contains(id) else { continue }
                let audio = session.appendingPathComponent(id.uuidString + ".m4a")
                guard manager.fileExists(atPath: audio.path) else { continue }
                try manager.removeItem(at: audio)
                removed += 1
            }
        }
        return removed
    }

    public func receive(fileURL: URL, chunk: RecordingSession.Chunk) throws -> URL {
        guard chunk.sequence > 0, chunk.duration.isFinite, chunk.duration > 0,
              chunk.end >= chunk.start,
              chunk.duration <= chunk.end.timeIntervalSince(chunk.start) + 1,
              chunk.checksum.count == 64,
              chunk.checksum.allSatisfy({ "0123456789abcdef".contains($0) }),
              chunk.localState == "committed" else { throw CocoaError(.fileReadCorruptFile) }
        let manager = FileManager.default
        let attributes = try manager.attributesOfItem(atPath: fileURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              (1...100_000_000).contains(size) else { throw CocoaError(.fileReadCorruptFile) }
        let sessionDirectory = directory.appendingPathComponent(chunk.sessionID.uuidString, isDirectory: true)
        try manager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let audio = sessionDirectory.appendingPathComponent(chunk.chunkID.uuidString + ".m4a")
        let metadata = sessionDirectory.appendingPathComponent(chunk.chunkID.uuidString + ".json")
        guard try checksum(fileURL) == chunk.checksum else { throw CocoaError(.fileReadCorruptFile) }

        if manager.fileExists(atPath: audio.path) {
            guard try checksum(audio) == chunk.checksum else { throw CocoaError(.fileReadCorruptFile) }
        } else {
            let staged = sessionDirectory.appendingPathComponent(UUID().uuidString + ".pending")
            defer { try? manager.removeItem(at: staged) }
            try manager.copyItem(at: fileURL, to: staged)
            guard try checksum(staged) == chunk.checksum else { throw CocoaError(.fileReadCorruptFile) }
            do { try manager.moveItem(at: staged, to: audio) }
            catch {
                guard manager.fileExists(atPath: audio.path),
                      try checksum(audio) == chunk.checksum else { throw error }
            }
        }

        if manager.fileExists(atPath: metadata.path) {
            guard try JSONDecoder().decode(RecordingSession.Chunk.self,
                from: Data(contentsOf: metadata)) == chunk else { throw CocoaError(.fileReadCorruptFile) }
        } else {
            try JSONEncoder().encode(chunk).write(to: metadata, options: .atomic)
        }
        return audio
    }

    private func checksum(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            let bytes = try handle.read(upToCount: 1_048_576) ?? Data()
            if bytes.isEmpty { break }
            hash.update(data: bytes)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

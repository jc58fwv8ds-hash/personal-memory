import Foundation
import CryptoKit

/// One portable resource: versioned metadata followed by the immutable audio bytes.
public enum ChunkTransferBundle {
    private static let magic = Data("PMCHNK01".utf8)
    public enum Failure: Error { case invalidFormat, checksumMismatch }

    public static func pack(audio: URL, chunk: RecordingSession.Chunk, destination: URL) throws {
        let metadata = try JSONEncoder().encode(chunk)
        guard metadata.count <= 65_536 else { throw Failure.invalidFormat }
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staged = destination.appendingPathExtension("pending")
        defer { try? manager.removeItem(at: staged) }
        guard manager.createFile(atPath: staged.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: staged)
        let input = try FileHandle(forReadingFrom: audio)
        defer { try? output.close(); try? input.close() }
        try output.write(contentsOf: magic)
        let size = UInt32(metadata.count)
        try output.write(contentsOf: Data([UInt8(size >> 24), UInt8((size >> 16) & 255),
                                           UInt8((size >> 8) & 255), UInt8(size & 255)]))
        try output.write(contentsOf: metadata)
        var hash = SHA256()
        var total = 0
        while true {
            let bytes = try input.read(upToCount: 1_048_576) ?? Data()
            if bytes.isEmpty { break }
            total += bytes.count
            guard total <= 100_000_000 else { throw Failure.invalidFormat }
            hash.update(data: bytes)
            try output.write(contentsOf: bytes)
        }
        guard total > 0, digest(hash) == chunk.checksum else { throw Failure.checksumMismatch }
        try output.synchronize()
        try manager.moveItem(at: staged, to: destination)
    }

    public static func unpack(bundle: URL, audioDestination: URL) throws -> RecordingSession.Chunk {
        let input = try FileHandle(forReadingFrom: bundle)
        defer { try? input.close() }
        guard try input.read(upToCount: 8) == magic,
              let sizeBytes = try input.read(upToCount: 4), sizeBytes.count == 4 else {
            throw Failure.invalidFormat
        }
        let size = sizeBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size > 0, size <= 65_536,
              let metadata = try input.read(upToCount: Int(size)), metadata.count == size else {
            throw Failure.invalidFormat
        }
        let chunk = try JSONDecoder().decode(RecordingSession.Chunk.self, from: metadata)
        let manager = FileManager.default
        try manager.createDirectory(at: audioDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staged = audioDestination.appendingPathExtension("pending")
        defer { try? manager.removeItem(at: staged) }
        guard manager.createFile(atPath: staged.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: staged)
        defer { try? output.close() }
        var hash = SHA256()
        var total = 0
        while true {
            let bytes = try input.read(upToCount: 1_048_576) ?? Data()
            if bytes.isEmpty { break }
            total += bytes.count
            guard total <= 100_000_000 else { throw Failure.invalidFormat }
            hash.update(data: bytes)
            try output.write(contentsOf: bytes)
        }
        guard total > 0, digest(hash) == chunk.checksum else { throw Failure.checksumMismatch }
        try output.synchronize()
        try manager.moveItem(at: staged, to: audioDestination)
        return chunk
    }

    private static func digest(_ hash: SHA256) -> String {
        hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

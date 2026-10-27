import Foundation

/// Deleting audio from the Mac reaches the shared folder and the iPhone (2026-10-27). The Mac moves the shared copy of
/// each piece to the Trash and leaves `<chunkID>.retired`; the iPhone reads the marks, deletes its own copy and clears them.
extension RelayFolder {
    /// Marks each piece as retired and hands its `<chunkID>.pmchunk` (if there) to `trash`; returns how many were handed.
    @discardableResult
    public static func retire(_ chunkIDs: [UUID], in folder: URL, trash: (URL) throws -> Void) throws -> Int {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var handed = 0
        for id in Set(chunkIDs) {
            let mark = folder.appendingPathComponent(id.uuidString + ".retired", isDirectory: false)
            try Data().write(to: mark, options: .atomic)
            let bundle = folder.appendingPathComponent(id.uuidString + ".pmchunk", isDirectory: false)
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: bundle.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                try trash(bundle)
                handed += 1
            }
        }
        return handed
    }

    /// The pieces marked retired in the folder, sorted by `uuidString`.
    public static func retiredMarks(in folder: URL) throws -> [UUID] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.path) else { return [] }
        let entries = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        var marks: [UUID] = []
        for entry in entries {
            let name = entry.lastPathComponent
            guard let values = try? entry.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true,
                  name.hasSuffix(".retired"),
                  let id = UUID(uuidString: String(name.dropLast(".retired".count))) else { continue }
            marks.append(id)
        }
        return marks.sorted { $0.uuidString < $1.uuidString }
    }

    /// Removes one piece's mark once the iPhone has deleted its copy.
    public static func clearMark(_ chunkID: UUID, in folder: URL) throws {
        let mark = folder.appendingPathComponent(chunkID.uuidString + ".retired", isDirectory: false)
        if FileManager.default.fileExists(atPath: mark.path) {
            try FileManager.default.removeItem(at: mark)
        }
    }
}

import Foundation

public struct RecordingItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let savedAt: Date
    public let byteCount: Int64
}

public enum RecordingCatalog {
    public static func recordings(in directory: URL) throws -> [RecordingItem] {
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try FileManager.default.attributesOfItem(atPath: directory.path)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return []
        }

        guard let type = attrs[.type] as? FileAttributeType, type == .typeDirectory else {
            throw CocoaError(.fileReadInvalidFileName)
        }

        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: []
        )

        var items: [RecordingItem] = []
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.hasSuffix(".m4a") else { continue }
            
            let baseName = String(name.dropLast(4))
            guard let id = UUID(uuidString: baseName) else { continue }

            do {
                let fileAttrs = try FileManager.default.attributesOfItem(atPath: entry.path)
                guard let type = fileAttrs[.type] as? FileAttributeType, type == .typeRegular else { continue }
                
                guard let sizeValue = fileAttrs[.size] as? NSNumber,
                      (1...20_000_000).contains(sizeValue.int64Value) else {
                    continue
                }
                let byteCount = sizeValue.int64Value

                let savedAt = fileAttrs[.modificationDate] as? Date ?? .distantPast
                items.append(RecordingItem(id: id, url: entry, savedAt: savedAt, byteCount: byteCount))
            } catch {
                throw error
            }
        }

        let sessions = directory.appendingPathComponent("Sessions", isDirectory: true)
        if let sessionAttrs = try? FileManager.default.attributesOfItem(atPath: sessions.path),
           sessionAttrs[.type] as? FileAttributeType == .typeDirectory {
            let folders = try FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil)
            for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil {
                let folderAttrs = try FileManager.default.attributesOfItem(atPath: folder.path)
                guard folderAttrs[.type] as? FileAttributeType == .typeDirectory else { continue }
                let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                for audio in files where audio.pathExtension == "m4a" {
                    guard let id = UUID(uuidString: audio.deletingPathExtension().lastPathComponent),
                          FileManager.default.fileExists(atPath: folder.appendingPathComponent(id.uuidString + ".json").path)
                    else { continue }
                    let fileAttrs = try FileManager.default.attributesOfItem(atPath: audio.path)
                    guard fileAttrs[.type] as? FileAttributeType == .typeRegular,
                          let size = (fileAttrs[.size] as? NSNumber)?.int64Value,
                          (1...100_000_000).contains(size) else { continue }
                    items.append(RecordingItem(id: id, url: audio,
                        savedAt: fileAttrs[.modificationDate] as? Date ?? .distantPast, byteCount: size))
                }
            }
        }

        return items.sorted { lhs, rhs in
            if lhs.savedAt != rhs.savedAt {
                return lhs.savedAt > rhs.savedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

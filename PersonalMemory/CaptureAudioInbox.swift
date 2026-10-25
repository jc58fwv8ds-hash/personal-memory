import Foundation

public struct CaptureAudioInbox: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("PersonalMemory/AudioInbox", isDirectory: true)
    }

    public func receive(fileURL: URL, id: UUID) throws -> URL {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let attrs = try fm.attributesOfItem(atPath: fileURL.path)
        guard let type = attrs[.type] as? FileAttributeType, type == .typeRegular else {
            throw CocoaError(.fileReadCorruptFile)
        }

        guard let size = (attrs[.size] as? NSNumber)?.intValue,
              size >= 1, size <= 20_000_000 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let targetURL = directory.appendingPathComponent("\(id.uuidString).m4a")
        
        var targetIsDir: ObjCBool = false
        if fm.fileExists(atPath: targetURL.path, isDirectory: &targetIsDir) {
            guard !targetIsDir.boolValue else { throw CocoaError(.fileReadCorruptFile) }
            
            let targetAttrs = try fm.attributesOfItem(atPath: targetURL.path)
            guard let targetType = targetAttrs[.type] as? FileAttributeType, targetType == .typeRegular else {
                throw CocoaError(.fileReadCorruptFile)
            }

            guard (targetAttrs[.size] as? NSNumber)?.intValue == size else {
                throw CocoaError(.fileWriteNoPermission)
            }

            let sourceData = try Data(contentsOf: fileURL)
            let targetData = try Data(contentsOf: targetURL)
            if sourceData == targetData {
                return targetURL
            } else {
                throw CocoaError(.fileWriteNoPermission)
            }
        }

        let tmpUUID = UUID()
        let tmpURL = directory.appendingPathComponent("\(tmpUUID.uuidString).tmp")
        
        do {
            try fm.copyItem(at: fileURL, to: tmpURL)
            try fm.moveItem(at: tmpURL, to: targetURL)
            return targetURL
        } catch {
            if fm.fileExists(atPath: tmpURL.path) {
                try? fm.removeItem(at: tmpURL)
            }
            throw error
        }
    }

    public func recordings() throws -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir) else { return [] }
        guard isDir.boolValue else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])
        var result: [URL] = []
        
        for url in contents {
            guard url.pathExtension == "m4a" else { continue }
            guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil else { continue }
            
            let attrs = try fm.attributesOfItem(atPath: url.path)
            guard let type = attrs[.type] as? FileAttributeType, type == .typeRegular else {
                continue
            }
            result.append(url)
        }
        
        return result
    }
}

import Foundation

enum RecordingExport {
    enum ExportError: Error, Equatable {
        case invalidSource
        case sourceIsDirectory
        case sourceIsEmpty
        case sourceTooLarge
        case sourceIsSymbolicLink
        case destinationInvalid
        case destinationExists
        case copyFailed
    }

    static func prepare(recording: URL, in destinationFolder: URL) throws -> URL {
        let fileManager = FileManager.default

        // Validate URLs are file URLs
        guard recording.isFileURL else {
            throw ExportError.invalidSource
        }
        guard destinationFolder.isFileURL else {
            throw ExportError.destinationInvalid
        }

        // Validate destination folder exists and is a directory (not symlink)
        let destAttrs = try fileManager.attributesOfItem(atPath: destinationFolder.path)
        guard let destType = destAttrs[.type] as? FileAttributeType, destType == .typeDirectory else {
            throw ExportError.destinationInvalid
        }

        // Validate source exists and is a regular file (not directory, not symlink)
        let sourceAttrs = try fileManager.attributesOfItem(atPath: recording.path)
        guard let sourceType = sourceAttrs[.type] as? FileAttributeType else {
            throw ExportError.invalidSource
        }

        if sourceType == .typeDirectory {
            throw ExportError.sourceIsDirectory
        }

        // Check if source is a symbolic link (refuse linked source)
        guard sourceType == .typeRegular else {
            throw ExportError.sourceIsSymbolicLink
        }

        // Check if filename matches UUID.m4a pattern
        let lastPathComponent = recording.lastPathComponent
        guard isValidUUIDM4aFilename(lastPathComponent) else {
            throw ExportError.invalidSource
        }

        // Check size: must not be empty and must not exceed 20,000,000 bytes
        guard let fileSizeValue = sourceAttrs[.size] as? NSNumber else {
            throw ExportError.sourceIsEmpty
        }
        
        let fileSize = fileSizeValue.uint64Value
        guard fileSize > 0 else {
            throw ExportError.sourceIsEmpty
        }
        
        let maxAllowedSize: UInt64 = 20_000_000 // 20,000,000 bytes
        guard fileSize <= maxAllowedSize else {
            throw ExportError.sourceTooLarge
        }

        // Determine destination URL
        let destinationURL = destinationFolder.appendingPathComponent(lastPathComponent)
        
        // Check if destination already exists (do not overwrite)
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw ExportError.destinationExists
        }

        // Perform copy. If it fails, original remains untouched.
        do {
            try fileManager.copyItem(at: recording, to: destinationURL)
        } catch {
            throw ExportError.copyFailed
        }

        return destinationURL
    }

    private static func isValidUUIDM4aFilename(_ name: String) -> Bool {
        // Must end with .m4a
        guard name.hasSuffix(".m4a") else {
            return false
        }
        
        let baseName = String(name.dropLast(4)) // remove ".m4a"
        
        // Try to parse as UUID
        guard UUID(uuidString: baseName) != nil else {
            return false
        }
        
        return true
    }
}

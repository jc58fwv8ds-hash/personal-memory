import Foundation

public struct MemoryEventStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() throws -> URL {
        let supportDir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return supportDir.appendingPathComponent("PersonalMemory/events.json")
    }

    public func load() throws -> [MemoryEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONDecoder().decode([MemoryEvent].self, from: data)
        } catch {
            throw MemoryStoreError.corruptedData
        }
    }

    public func save(_ events: [MemoryEvent]) throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try load()
        }
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parentDir,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(events)
        try data.write(to: fileURL, options: .atomic)
    }
}

public enum MemoryStoreError: Error {
    case corruptedData
}
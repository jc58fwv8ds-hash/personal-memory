import Foundation
import CryptoKit

public struct CalendarDocument: Codable, Sendable {
    public var version = 1
    public var recordingHash: String
    public var originalName: String
    public var referenceDate: Date
    public var timeZoneID: String
    public var transcript = ""
    public var proposals: [CalendarProposal] = []
    /// Written before the external effect. Uncertain submissions must never auto-retry.
    public var submissions: [UUID: String] = [:]
    public init(recordingHash: String, originalName: String, referenceDate: Date, timeZoneID: String) {
        self.recordingHash = recordingHash; self.originalName = originalName
        self.referenceDate = referenceDate; self.timeZoneID = timeZoneID
    }
}

public struct RecordingWorkspace: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public func importRecording(_ source: URL) throws -> CalendarDocument {
        let fm = FileManager.default
        guard source.isFileURL, source.pathExtension.lowercased() == "m4a" else { throw WorkspaceError.invalidAudio }
        let attributes = try fm.attributesOfItem(atPath: source.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, (1...20_000_000).contains(size.intValue) else {
            throw WorkspaceError.invalidAudio
        }
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        guard data.count == size.intValue else { throw WorkspaceError.invalidAudio }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try prepareRoot()
        let audio = try audioURL(hash)
        if fm.fileExists(atPath: audio.path) {
            guard try Data(contentsOf: audio) == data else { throw WorkspaceError.corrupt }
        } else {
            let staging = root.appendingPathComponent(UUID().uuidString + ".tmp")
            defer { try? fm.removeItem(at: staging) }
            try data.write(to: staging, options: .withoutOverwriting)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
            let handle = try FileHandle(forWritingTo: staging)
            do { try handle.synchronize(); try handle.close() }
            catch { try? handle.close(); throw error }
            try fm.moveItem(at: staging, to: audio) // Same directory; refuses an existing final name.
        }
        let documentURL = try documentURL(hash)
        if fm.fileExists(atPath: documentURL.path) {
            let document = try JSONDecoder().decode(CalendarDocument.self, from: Data(contentsOf: documentURL))
            guard document.version == 1, document.recordingHash == hash else { throw WorkspaceError.corrupt }
            return document
        }
        let document = CalendarDocument(recordingHash: hash, originalName: source.lastPathComponent,
            referenceDate: attributes[.creationDate] as? Date ?? Date(), timeZoneID: TimeZone.current.identifier)
        try save(document)
        return document
    }
    public func save(_ document: CalendarDocument) throws {
        try prepareRoot()
        let url = try documentURL(document.recordingHash)
        try JSONEncoder().encode(document).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    /// The saved recordings whose reference date falls on the day that contains `day` (in `calendar`'s time zone).
    public func documents(onDayOf day: Date, calendar: Calendar) throws -> [CalendarDocument] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        let names = try fm.contentsOfDirectory(atPath: root.path)
        var result: [CalendarDocument] = []
        for name in names where name.hasSuffix(".json") {
            let hash = String(name.dropLast(5))
            guard hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }) else { continue }
            let url = root.appendingPathComponent(name)
            let attributes = (try? fm.attributesOfItem(atPath: url.path)) ?? [:]
            guard attributes[.type] as? FileAttributeType == .typeRegular else { continue }
            guard let data = try? Data(contentsOf: url),
                  let document = try? JSONDecoder().decode(CalendarDocument.self, from: data),
                  document.version == 1, document.recordingHash == hash,
                  calendar.isDate(document.referenceDate, inSameDayAs: day) else { continue }
            result.append(document)
        }
        return result.sorted { ($0.referenceDate, $0.recordingHash) < ($1.referenceDate, $1.recordingHash) }
    }
    public func audioURL(_ hash: String) throws -> URL {
        try checkedURL(hash, extension: "m4a")
    }
    private func documentURL(_ hash: String) throws -> URL { try checkedURL(hash, extension: "json") }
    private func checkedURL(_ hash: String, extension suffix: String) throws -> URL {
        guard hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw WorkspaceError.corrupt }
        return root.appendingPathComponent(hash).appendingPathExtension(suffix)
    }
    private func prepareRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw WorkspaceError.corrupt }
    }
    public enum WorkspaceError: LocalizedError {
        case invalidAudio, corrupt
        public var errorDescription: String? {
            switch self {
            case .invalidAudio: "20MB以内の空でないm4a録音を選んでください。リンクは読み込めません。"
            case .corrupt: "保存内容を安全に確認できません。上書きせず停止しました。"
            }
        }
    }
}

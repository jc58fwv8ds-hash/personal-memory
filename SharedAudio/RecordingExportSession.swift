#if os(iOS)
import Combine
import Foundation

struct SharedRecording: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class RecordingExportSession: ObservableObject {
    @Published var shared: SharedRecording?
    @Published private(set) var isPreparing = false
    @Published private(set) var message: String?
    private var directory: URL?
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func prepare(_ source: URL) {
        guard !isPreparing, shared == nil else { return }
        let id = UUID()
        generation = id
        isPreparing = true
        message = nil
        task = Task { [weak self] in
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingShare-\(id)")
            do {
                let url = try await Task.detached(priority: .utility) {
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                           attributes: [.posixPermissions: 0o700])
                    return try RecordingExport.prepare(recording: source, in: root)
                }.value
                try Task.checkCancellation()
                guard let self, self.generation == id else {
                    Self.removeCopy(root)
                    return
                }
                self.directory = root
                self.isPreparing = false
                self.shared = SharedRecording(url: url)
            } catch {
                Self.removeCopy(root)
                guard let self, self.generation == id else { return }
                self.isPreparing = false
                if !(error is CancellationError) {
                    self.message = "共有用のコピーを用意できませんでした。録音の原本は変更していません。"
                }
            }
        }
    }

    func dismiss() {
        if let directory { Self.removeCopy(directory) }
        directory = nil
        shared = nil
        message = "共有画面を閉じました。Mac側で受信を確認してください。原本は保持しています。"
    }

    func cancelPreparation() {
        task?.cancel()
        generation = UUID()
        isPreparing = false
    }

    private static func removeCopy(_ directory: URL) {
        // Only this session's newly created staging directory, never the recording inbox.
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: directory) }
    }
}
#endif

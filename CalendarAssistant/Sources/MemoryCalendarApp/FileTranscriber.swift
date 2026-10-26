import Foundation
@preconcurrency import Speech
import AVFoundation

/// File-only, on-device recognition. Long chunks are split below Speech's one-minute limit.
@MainActor final class FileTranscriber {
    private var recognition: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<String, any Error>?
    private var deadline: Task<Void, Never>?
    private var activeID: UUID?
    func transcribe(_ url: URL) async throws -> String {
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 900 else {
            throw CalendarFlowError.message("録音は15分以内の区切りで読み込んでください。")
        }
        let permission = await withCheckedContinuation { continuation in
            // Speech delivers on an arbitrary queue: never inherit this class's MainActor isolation.
            SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
        }
        try Task.checkCancellation()
        guard permission == .authorized else {
            throw CalendarFlowError.message("文字起こしの許可が必要です。システム設定で許可するか、文章を貼り付けてください。")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")),
              recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            throw CalendarFlowError.message("日本語の端末内文字起こしを利用できません。録音は外部送信せず停止しました。文章を貼り付けて続けられます。")
        }
        if duration <= 55 { return try await recognizeShort(url, recognizer: recognizer) }
        var sections: [String] = []
        var offset = 0.0
        while offset < duration {
            try Task.checkCancellation()
            let length = min(50.0, duration - offset)
            let segment = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".m4a")
            defer { try? FileManager.default.removeItem(at: segment) }
            guard let export = AVAssetExportSession(asset: AVURLAsset(url: url),
                                                    presetName: AVAssetExportPresetPassthrough) else {
                throw CalendarFlowError.message("録音を文字起こし用に分割できませんでした。")
            }
            export.timeRange = CMTimeRange(start: CMTime(seconds: offset, preferredTimescale: 600),
                                           duration: CMTime(seconds: length, preferredTimescale: 600))
            try await export.export(to: segment, as: .m4a)
            let text = try await recognizeShort(segment, recognizer: recognizer)
            if !text.isEmpty { sections.append("[\(Int(offset / 60)):" + String(format: "%02d", Int(offset) % 60) + "] " + text) }
            offset += length
        }
        return sections.joined(separator: "\n")
    }

    private func recognizeShort(_ url: URL, recognizer: SFSpeechRecognizer) async throws -> String {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeID = id
                self.continuation = continuation
                recognition = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
                    var text = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                    // A quiet stretch of a long day is not a failure (Speech reports "No speech detected", 1110).
                    if text == nil, let error = error as NSError?, error.code == 1110 { text = "" }
                    let failure = error?.localizedDescription
                    Task { @MainActor in
                        if let text { self?.finish(.success(text), id: id) }
                        else if let failure { self?.finish(.failure(CalendarFlowError.message(failure)), id: id) }
                    }
                }
                deadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(75)) } catch { return }
                    self?.finish(.failure(CalendarFlowError.message("文字起こしが時間内に完了しませんでした。文章を貼り付けて続けられます。")), id: id)
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish(.failure(CancellationError()), id: id) } }
    }
    private func finish(_ result: Result<String, any Error>, id: UUID) {
        guard activeID == id, let pending = continuation else { return }
        activeID = nil
        continuation = nil
        deadline?.cancel(); deadline = nil
        recognition?.cancel(); recognition = nil
        pending.resume(with: result)
    }
}

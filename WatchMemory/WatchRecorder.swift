import Foundation
import AVFoundation
import Combine

/// Only the user's stop button ends a recording (2026-10-25). An interruption (a timer or alarm sounding, a call) or an
/// engine failure closes the current piece, keeps it, and starts recording again at once, retrying with a short back-off
/// while the microphone is still taken.
@MainActor
final class WatchRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false
    @Published private(set) var status = "録音できます"
    @Published private(set) var lastRecording: URL?
    /// The user started recording and has not pressed stop; true also while waiting to resume.
    @Published private(set) var wantsRecording = false
    private let engine = WatchRecordingEngine()
    private var cancellation: RecordingCancellation?
    private var requestID: UUID?
    private var waitingForPermission = false
    private var resume: Task<Void, Never>?
    private var failedResumes = 0
    private var observers: [AnyCancellable] = []

    init() {
        // Recording continues in the background (WKBackgroundModes audio), so interruptions are handled here rather
        // than in a view that may not be on screen.
        let center = NotificationCenter.default
        observers.append(center.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let began = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) != .ended
                MainActor.assumeIsolated { began ? self?.interrupted() : self?.resumeNow() }
            })
    }

    static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("PersonalMemory/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func start() async {
        wantsRecording = true
        failedResumes = 0
        await begin()
    }

    /// The user's stop button: the only way a recording ends.
    func stop() {
        wantsRecording = false
        resume?.cancel(); resume = nil
        guard isBusy else { status = "録音を終了しました。"; return }
        cancellation?.cancel()
        if waitingForPermission { end("開始を中止しました。もう一度押すと録音できます。"); return }
        status = "停止を要求しました。音声処理の終了を待っています。"
        engine.stop()
    }

    private func begin() async {
#if targetEnvironment(simulator)
        wantsRecording = false
        status = "Simulatorでは録音を停止中です。ペアリングした実機で確認してください。"
#else
        guard !isBusy else { return }
        let id = UUID()
        let token = RecordingCancellation()
        requestID = id
        cancellation = token
        isBusy = true
        waitingForPermission = true
        status = "マイクの許可を確認しています。"
        let granted = await AVAudioApplication.requestRecordPermission()
        guard requestID == id else { return }
        waitingForPermission = false
        guard granted, !token.isCancelled else {
            if !granted { wantsRecording = false }
            end(token.isCancelled ? "開始を中止しました。" : "マイクが許可されていません。Watchの設定を確認してください。")
            return
        }
        do {
            let directory = try Self.directory()
            status = "録音を準備しています。"
            engine.start(directory: directory, cancellation: token) { [weak self] event in
                Task { @MainActor in self?.receive(event, id: id) }
            }
        } catch { end("保存先を用意できませんでした。"); scheduleResume() }
#endif
    }

    /// Something else took the microphone: keep what was recorded and come back as soon as possible.
    private func interrupted() {
        guard wantsRecording, isBusy, !waitingForPermission else { return }
        status = "中断されました。ここまでを保存して、すぐに再開します。"
        engine.stop()
    }

    private func resumeNow() {
        guard wantsRecording, !isBusy else { return }
        resume?.cancel(); resume = nil
        Task { await begin() }
    }

    /// Retries 1, 2, 4, 8 and then every 10 seconds until recording runs again or the user presses stop.
    private func scheduleResume() {
        guard wantsRecording, resume == nil else { return }
        let delay = min(10, 1 << min(failedResumes, 4))
        failedResumes += 1
        status = "録音を再開しています(\(delay)秒後)。止めるには「停止して残す」。"
        resume = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.resume = nil
            await self.begin()
        }
    }

    private func receive(_ event: WatchRecordingEngine.Event, id: UUID) {
        guard requestID == id else { return }
        switch event {
        case .started:
            if cancellation?.isCancelled == true { engine.stop(); return }
            isRecording = true
            failedResumes = 0
            status = "録音中…"
        case .chunkFinished(let url):
            lastRecording = url
            status = "区切りを保存しました。録音を続けています。"
        case .finished(let url):
            lastRecording = url
            end(wantsRecording ? "ここまでを保存しました。" : "録音を保存しました。")
            scheduleResume()
        case .failed(let message):
            end(message)
            scheduleResume()
        }
    }

    private func end(_ message: String) {
        isBusy = false
        isRecording = false
        waitingForPermission = false
        cancellation = nil
        requestID = nil
        status = message
    }
}

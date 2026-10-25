import AVFoundation
import Foundation

enum PlaybackEvent: Sendable {
    case progress(elapsed: TimeInterval, duration: TimeInterval)
    case finished
    case failed(String)
}

protocol RecordingPlaybackProviding: Sendable {
    func play(_ url: URL, receive: @escaping @Sendable (PlaybackEvent) -> Void)
    func stop(completion: @escaping @Sendable () -> Void)
}

/// Audio objects and timer are confined to AudioWorkQueue, never the UI executor.
final class RecordingPlaybackEngine: RecordingPlaybackProviding, @unchecked Sendable {
    private var player: AVAudioPlayer?
    private var timer: DispatchSourceTimer?
    private var receive: (@Sendable (PlaybackEvent) -> Void)?
    private var ownsSession = false

    func play(_ url: URL, receive: @escaping @Sendable (PlaybackEvent) -> Void) {
        AudioWorkQueue.shared.async { [self] in
            clear()
            self.receive = receive
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                guard attrs[.type] as? FileAttributeType == .typeRegular,
                      let size = (attrs[.size] as? NSNumber)?.intValue,
                      (1...20_000_000).contains(size), url.pathExtension == "m4a",
                      UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
                else { throw CocoaError(.fileReadCorruptFile) }
                let audio = try AVAudioPlayer(contentsOf: url)
                // Pieces are cut about every 10 minutes (the old 61-second cap from the 60-second era rejected every
                // longer piece as "not in the correct format", 2026-10-25).
                guard audio.duration.isFinite, audio.duration > 0, audio.duration <= 3_600
                else { throw CocoaError(.fileReadCorruptFile) }
#if os(iOS) || os(watchOS)
                // Foreground preview, not long-form/background playback requiring Bluetooth.
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                ownsSession = true
                try AVAudioSession.sharedInstance().setActive(true)
#endif
                player = audio
                guard audio.play() else { throw CocoaError(.fileReadUnknown) }
                receive(.progress(elapsed: 0, duration: audio.duration))
                let timer = DispatchSource.makeTimerSource(queue: AudioWorkQueue.shared)
                timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
                timer.setEventHandler { [weak self] in self?.tick() }
                self.timer = timer
                timer.resume()
            } catch {
                clear()
                receive(.failed("再生できませんでした。音声は残っています。\(error.localizedDescription)"))
            }
        }
    }

    func stop(completion: @escaping @Sendable () -> Void) {
        AudioWorkQueue.shared.async { [self] in clear(); completion() }
    }

    private func tick() {
        guard let audio = player else { return }
        if audio.isPlaying {
            receive?(.progress(elapsed: audio.currentTime, duration: audio.duration))
        } else {
            let callback = receive
            clear()
            callback?(.finished)
        }
    }

    private func clear() {
        timer?.cancel()
        timer = nil
        player?.stop()
        player = nil
        receive = nil
#if os(iOS) || os(watchOS)
        if ownsSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsSession = false
        }
#endif
    }
}

import Foundation
import AVFoundation
import CryptoKit

/// All mutable recording state belongs to AudioWorkQueue, never the UI executor.
final class WatchRecordingEngine: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    enum Event: Sendable { case started, chunkFinished(URL), finished(URL), failed(String) }
    private let queue = AudioWorkQueue.shared
    private var recorder: AVAudioRecorder?
    private var completion: (@Sendable (Event) -> Void)?
    private var session: RecordingSession?
    private var directory: URL?
    private var stopping = false
    private let chunkDuration: TimeInterval = 600

    func start(directory: URL, cancellation: RecordingCancellation,
               receive: @escaping @Sendable (Event) -> Void) {
        queue.async { [self] in
            guard recorder == nil else { receive(.failed("前の録音を終了しています。")); return }
            completion = receive
            do {
                guard !cancellation.isCancelled else { throw CancellationError() }
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.record, mode: .default)
                try audioSession.setActive(true)
                guard !cancellation.isCancelled else { throw CancellationError() }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                self.directory = directory
                let newSession = RecordingSession(start: Date())
                session = newSession
                stopping = false
                try RecordingSessionStore(directory: directory.appendingPathComponent("Sessions"))
                    .save(newSession)
                try beginChunk()
                if cancellation.isCancelled { stopOnQueue(); return }
                receive(.started)
            } catch {
                recorder?.stop()
                recorder = nil
                session = nil
                self.directory = nil
                try? AVAudioSession.sharedInstance().setActive(false)
                let message = error is CancellationError ? "録音の開始を中止しました。" : "録音を開始できませんでした: \(error.localizedDescription)"
                complete(.failed(message))
            }
        }
    }

    func stop() { queue.async { [self] in stopOnQueue() } }

    private func beginChunk() throws {
        guard let directory else { throw CocoaError(.fileWriteUnknown) }
        let url = directory.appendingPathComponent(UUID().uuidString + ".pending.m4a")
        let audio = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 24000
        ])
        audio.delegate = self
        guard audio.record(forDuration: chunkDuration) else { throw CocoaError(.fileWriteUnknown) }
        recorder = audio
    }

    private func stopOnQueue() {
        guard let audio = recorder else { return }
        stopping = true
        let url = audio.url
        audio.stop()
        finish(url: url, success: true)
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        queue.async { [self] in finish(url: url, success: flag) }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let url = recorder.url
        queue.async { [self] in finish(url: url, success: false) }
    }

    private func finish(url: URL, success: Bool) {
        guard recorder?.url == url else { return }
        recorder = nil
        do {
            guard success, let directory, var current = session,
                  url.lastPathComponent.hasSuffix(".pending.m4a"),
                  let id = UUID(uuidString: url.deletingPathExtension().deletingPathExtension().lastPathComponent)
            else { throw CocoaError(.fileReadCorruptFile) }
            let duration = try AVAudioPlayer(contentsOf: url).duration
            guard duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
            let hash = try checksum(url)
            try current.finalizeCommittedChunk(id: id, end: Date(), duration: duration,
                checksum: hash, boundary: stopping ? .stop : .rollover)
            let chunk = current.chunks[current.chunks.count - 1]
            let manifest = directory.appendingPathComponent(id.uuidString + ".json")
            let final = directory.appendingPathComponent(id.uuidString + ".m4a")
            // The transfer queue sees a final audio name only after its manifest exists.
            try JSONEncoder().encode(chunk).write(to: manifest, options: .atomic)
            try FileManager.default.moveItem(at: url, to: final)
            try RecordingSessionStore(directory: directory.appendingPathComponent("Sessions"))
                .save(current)
            session = current
            if stopping {
                try? AVAudioSession.sharedInstance().setActive(false)
                session = nil
                self.directory = nil
                complete(.finished(final))
            } else {
                completion?(.chunkFinished(final))
                try beginChunk()
            }
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false)
            session = nil
            self.directory = nil
            complete(.failed("録音を確定できませんでした。途中のファイルは保持しています。"))
        }
    }

    private func checksum(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            let bytes = try handle.read(upToCount: 1_048_576) ?? Data()
            if bytes.isEmpty { break }
            hash.update(data: bytes)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func complete(_ event: Event) {
        let receive = completion
        completion = nil
        receive?(event)
    }
}

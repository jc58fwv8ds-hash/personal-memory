import Foundation
import AVFoundation
import CryptoKit

/// All mutable recording state belongs to AudioWorkQueue, never the UI executor.
///
/// 2026-10-27: the microphone runs without a break for the whole recording (AVAudioEngine input tap) and only the file
/// changes every 10 minutes. The earlier AVAudioRecorder version stopped and restarted the recorder at each piece; with
/// the screen off, watchOS suspended the app in that gap and every recording of 2026-10-26 ended after its first piece.
final class WatchRecordingEngine: NSObject, @unchecked Sendable {
    enum Event: Sendable { case started, chunkFinished(URL), finished(URL), failed(String) }
    private let queue = AudioWorkQueue.shared
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var framesInFile: AVAudioFramePosition = 0
    private var counter = ChunkFrameCounter(framesPerChunk: 1)
    private var completion: (@Sendable (Event) -> Void)?
    private var session: RecordingSession?
    private var configurationObserver: (any NSObjectProtocol)?
    private var directory: URL?
    private let chunkDuration: TimeInterval = 600

    func start(directory: URL, cancellation: RecordingCancellation,
               receive: @escaping @Sendable (Event) -> Void) {
        queue.async { [self] in
            guard engine == nil else { receive(.failed("前の録音を終了しています。")); return }
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
                try RecordingSessionStore(directory: directory.appendingPathComponent("Sessions")).save(newSession)

                let engine = AVAudioEngine()
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.fileWriteUnknown) }
                counter = ChunkFrameCounter(framesPerChunk: Int(format.sampleRate * chunkDuration))
                try openFile(format: format)
                input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                    // The tap's buffer is reused after this returns: copy it, then write on the work queue.
                    guard let self, let copy = Self.slice(buffer, from: 0, count: Int(buffer.frameLength)) else { return }
                    self.queue.async { self.write(copy) }
                }
                engine.prepare()
                try engine.start()
                self.engine = engine
                // A route or format change stops the engine without an interruption: keep the piece and let the
                // recorder start again, instead of "recording" silence.
                configurationObserver = NotificationCenter.default.addObserver(
                    forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
                    self?.stop()
                }
                if cancellation.isCancelled { stopOnQueue(); return }
                receive(.started)
            } catch {
                tearDown()
                let message = error is CancellationError ? "録音の開始を中止しました。" : "録音を開始できませんでした: \(error.localizedDescription)"
                complete(.failed(message))
            }
        }
    }

    /// The user's stop, or an interruption: keeps what was recorded and ends the session.
    func stop() { queue.async { [self] in stopOnQueue() } }

    private func write(_ buffer: AVAudioPCMBuffer) {
        guard engine != nil, file != nil else { return }
        var offset = 0
        for part in counter.take(Int(buffer.frameLength)) {
            do {
                if part.startsNewPiece {
                    let finished = try commitFile(boundary: .rollover)
                    completion?(.chunkFinished(finished))
                    try openFile(format: buffer.format)
                }
                if let piece = Self.slice(buffer, from: offset, count: part.frames) {
                    try file?.write(from: piece)
                    framesInFile += AVAudioFramePosition(part.frames)
                }
            } catch {
                fail("録音を保存できませんでした。ここまでの区切りは保持しています。")
                return
            }
            offset += part.frames
        }
    }

    private func stopOnQueue() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        do {
            let final = try commitFile(boundary: .stop)
            tearDown()
            complete(.finished(final))
        } catch {
            fail("録音を確定できませんでした。途中のファイルは保持しています。")
        }
    }

    private func openFile(format: AVAudioFormat) throws {
        guard let directory else { throw CocoaError(.fileWriteUnknown) }
        let url = directory.appendingPathComponent(UUID().uuidString + ".pending.m4a")
        file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000
        ], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        fileURL = url
        framesInFile = 0
    }

    /// Closes the current file and records it as a committed piece; returns its final URL.
    private func commitFile(boundary: RecordingSession.Boundary) throws -> URL {
        guard let directory, var current = session, let url = fileURL, let sampleRate = file?.processingFormat.sampleRate,
              let id = UUID(uuidString: url.deletingPathExtension().deletingPathExtension().lastPathComponent)
        else { throw CocoaError(.fileReadCorruptFile) }
        let duration = Double(framesInFile) / sampleRate
        // Releasing the only reference finishes the file on watchOS 10, which has no close().
        if #available(watchOS 11.0, *) { file?.close() }
        file = nil
        fileURL = nil
        guard duration > 0 else {
            // Nothing was written (stopped at once): no empty piece.
            try? FileManager.default.removeItem(at: url)
            throw CocoaError(.fileReadCorruptFile)
        }
        let hash = try checksum(url)
        try current.finalizeCommittedChunk(id: id, end: Date(), duration: duration, checksum: hash, boundary: boundary)
        let chunk = current.chunks[current.chunks.count - 1]
        let manifest = directory.appendingPathComponent(id.uuidString + ".json")
        let final = directory.appendingPathComponent(id.uuidString + ".m4a")
        // The transfer queue sees a final audio name only after its manifest exists.
        try JSONEncoder().encode(chunk).write(to: manifest, options: .atomic)
        try FileManager.default.moveItem(at: url, to: final)
        try RecordingSessionStore(directory: directory.appendingPathComponent("Sessions")).save(current)
        session = current
        return final
    }

    private func fail(_ message: String) {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        tearDown()
        complete(.failed(message))
    }

    private func tearDown() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        file = nil
        fileURL = nil
        session = nil
        directory = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    /// `count` frames of `buffer` from `from`, as a new buffer.
    private static func slice(_ buffer: AVAudioPCMBuffer, from start: Int, count: Int) -> AVAudioPCMBuffer? {
        guard count > 0, start >= 0, start + count <= Int(buffer.frameLength),
              let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(count)) else { return nil }
        out.frameLength = AVAudioFrameCount(count)
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let target = UnsafeMutableAudioBufferListPointer(out.mutableAudioBufferList)
        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        for (from, to) in zip(source, target) {
            guard let src = from.mData, let dst = to.mData else { return nil }
            memcpy(dst, src.advanced(by: start * bytesPerFrame), count * bytesPerFrame)
        }
        return out
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

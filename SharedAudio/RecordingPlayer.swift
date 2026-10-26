import Combine
import Foundation

@MainActor
final class RecordingPlayer: ObservableObject {
    @Published private(set) var selectedID: UUID?
    @Published private(set) var isBusy = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var status = "録音を選ぶと聴き直せます"
    /// The day being played piece after piece (2026-10-26): one day is one recording to the user.
    @Published private(set) var playingDay: Date?
    @Published private(set) var position = 0
    @Published private(set) var queue: [RecordingItem] = []
    private var requestID: UUID?
    private var stopping = false
    private let engine: any RecordingPlaybackProviding

    init(engine: any RecordingPlaybackProviding = RecordingPlaybackEngine()) {
        self.engine = engine
    }

    func play(_ item: RecordingItem) {
        guard !isBusy else { return }
        let request = UUID()
        requestID = request
        selectedID = item.id
        isBusy = true
        stopping = false
        elapsed = 0
        duration = 0
        status = "再生を準備しています"
        engine.play(item.url) { [weak self] event in
            Task { @MainActor in self?.receive(event, request: request) }
        }
    }

    /// Plays the pieces in order without a gap the user has to fill.
    func play(day: Date, pieces: [RecordingItem]) {
        guard !isBusy, let first = pieces.first else { return }
        playingDay = day
        queue = pieces
        position = 0
        play(first)
    }

    func stop() {
        guard isBusy, !stopping else { return }
        stopping = true
        status = "再生を停止しています"
        let request = requestID
        engine.stop { [weak self] in
            Task { @MainActor in
                guard let self, self.requestID == request else { return }
                self.finish("停止しました")
            }
        }
    }

    private func receive(_ event: PlaybackEvent, request: UUID) {
        guard requestID == request, !stopping else { return }
        switch event {
        case .progress(let elapsed, let duration):
            self.elapsed = elapsed
            self.duration = duration
            status = "再生中"
        case .finished:
            elapsed = duration
            if position + 1 < queue.count {
                isBusy = false
                requestID = nil
                position += 1
                play(queue[position])
            } else {
                finish("再生を終了しました")
            }
        case .failed(let message): finish(message)
        }
    }

    private func finish(_ message: String) {
        playingDay = nil
        queue = []
        position = 0
        isBusy = false
        stopping = false
        requestID = nil
        status = message
    }
}

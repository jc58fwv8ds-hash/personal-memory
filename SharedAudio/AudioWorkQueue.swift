import Foundation

/// Recording and playback share one session; serialize their OS operations too.
enum AudioWorkQueue {
    static let shared = DispatchQueue(label: "personal-memory.audio")
}

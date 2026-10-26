/// Cuts a continuous stream of audio frames into fixed-length pieces without stopping the microphone (2026-10-27).
/// Stopping the recorder every 10 minutes let watchOS suspend the app in the background and recording ended; now the
/// input keeps running and each incoming buffer is split where a piece is full.
public struct ChunkFrameCounter: Equatable, Sendable {
    public struct Part: Equatable, Sendable {
        /// How many frames of the buffer, in order, go into this part (always 1 or more).
        public let frames: Int
        /// Close the current piece and start a new one before writing this part.
        public let startsNewPiece: Bool
        public init(frames: Int, startsNewPiece: Bool) { self.frames = frames; self.startsNewPiece = startsNewPiece }
    }

    public let framesPerChunk: Int
    /// Frames already written to the current piece.
    public private(set) var framesInChunk = 0

    /// `framesPerChunk` below 1 is treated as 1.
    public init(framesPerChunk: Int) { self.framesPerChunk = max(1, framesPerChunk) }

    /// A new piece was started from outside (after an interruption): count from zero.
    public mutating func reset() { framesInChunk = 0 }

    /// Splits `frames` incoming frames into the parts to write, in order.
    public mutating func take(_ frames: Int) -> [Part] {
        guard frames > 0 else { return [] }
        var parts: [Part] = []
        var remaining = frames
        while remaining > 0 {
            let startsNewPiece = framesInChunk == framesPerChunk
            if startsNewPiece { framesInChunk = 0 }
            let capacity = framesPerChunk - framesInChunk
            let partFrames = min(remaining, capacity)
            parts.append(Part(frames: partFrames, startsNewPiece: startsNewPiece))
            framesInChunk += partFrames
            remaining -= partFrames
        }
        return parts
    }
}

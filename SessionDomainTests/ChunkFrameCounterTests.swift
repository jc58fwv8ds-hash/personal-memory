// Local Factory 課題 pm-watch-01 の見える試験と隠し試験(HarnessTasks/pm-watch-01)。
import Testing
@testable import SessionDomain
fileprivate typealias Part = ChunkFrameCounter.Part

@Test func framesWithinAPieceStayInIt() {
    var counter = ChunkFrameCounter(framesPerChunk: 100)
    #expect(counter.take(40) == [Part(frames: 40, startsNewPiece: false)])
    #expect(counter.take(40) == [Part(frames: 40, startsNewPiece: false)])
    #expect(counter.framesInChunk == 80)
}

@Test func aBufferCrossingTheBoundaryIsSplit() {
    var counter = ChunkFrameCounter(framesPerChunk: 100)
    _ = counter.take(90)
    #expect(counter.take(30) == [Part(frames: 10, startsNewPiece: false), Part(frames: 20, startsNewPiece: true)])
    #expect(counter.framesInChunk == 20)
}

@Test func aFullPieceIsClosedOnlyWhenMoreFramesCome() {
    var counter = ChunkFrameCounter(framesPerChunk: 100)
    #expect(counter.take(100) == [Part(frames: 100, startsNewPiece: false)])
    #expect(counter.framesInChunk == 100)
    #expect(counter.take(5) == [Part(frames: 5, startsNewPiece: true)])
    #expect(counter.framesInChunk == 5)
}

@Test func holdoutABufferLongerThanSeveralPiecesStartsEachOne() {
    var counter = ChunkFrameCounter(framesPerChunk: 10)
    _ = counter.take(7)
    #expect(counter.take(25) == [Part(frames: 3, startsNewPiece: false), Part(frames: 10, startsNewPiece: true),
                                 Part(frames: 10, startsNewPiece: true), Part(frames: 2, startsNewPiece: true)])
    #expect(counter.framesInChunk == 2)
}

@Test func holdoutEndingExactlyOnABoundaryLeavesThePieceFull() {
    var counter = ChunkFrameCounter(framesPerChunk: 10)
    #expect(counter.take(20) == [Part(frames: 10, startsNewPiece: false), Part(frames: 10, startsNewPiece: true)])
    #expect(counter.framesInChunk == 10)
}

@Test func holdoutNothingOrNegativeChangesNothing() {
    var counter = ChunkFrameCounter(framesPerChunk: 10)
    _ = counter.take(4)
    #expect(counter.take(0).isEmpty)
    #expect(counter.take(-3).isEmpty)
    #expect(counter.framesInChunk == 4)
}

@Test func holdoutResetStartsCountingAgain() {
    var counter = ChunkFrameCounter(framesPerChunk: 10)
    _ = counter.take(10)
    counter.reset()
    #expect(counter.take(4) == [Part(frames: 4, startsNewPiece: false)])
}

@Test func holdoutTooSmallChunkLengthBecomesOne() {
    var counter = ChunkFrameCounter(framesPerChunk: 0)
    #expect(counter.framesPerChunk == 1)
    #expect(counter.take(3) == [Part(frames: 1, startsNewPiece: false), Part(frames: 1, startsNewPiece: true),
                                Part(frames: 1, startsNewPiece: true)])
}

@Test func holdoutTenMinutesAt16kHzInRealisticBuffers() {
    var counter = ChunkFrameCounter(framesPerChunk: 16_000 * 600)
    var total = 0, pieces = 1
    for _ in 0..<(16_000 * 1_300 / 4_096) {
        for part in counter.take(4_096) { total += part.frames; if part.startsNewPiece { pieces += 1 } }
    }
    #expect(total == 16_000 * 1_300 / 4_096 * 4_096)
    #expect(pieces == 3)
}

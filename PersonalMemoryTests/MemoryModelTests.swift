import Foundation
import Testing
@testable import PersonalMemory

private func testUUID(_ final: String) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-" + final)!
}

private func makeEvent(id: UUID, time: TimeInterval) -> MemoryEvent {
    MemoryEvent(
        id: id,
        occurredAt: Date(timeIntervalSince1970: time),
        transcript: "event",
        importance: 50,
        tags: [],
        sourceCaptureIDs: []
    )
}

@Test func memoryCaptureRoundTrip() throws {
    let capture = MemoryCapture(
        id: testUUID("000000000001"),
        localAudioReference: " clips/one.m4a ",
        capturedAt: Date(timeIntervalSince1970: 1_000),
        device: .appleWatch,
        durationSeconds: 12.5,
        state: .queued
    )
    let data = try JSONEncoder().encode(capture)
    #expect(try JSONDecoder().decode(MemoryCapture.self, from: data) == capture)
    #expect(capture.localAudioReference == "clips/one.m4a")
}

@Test func memoryCaptureUnknownEnumsFallBack() throws {
    let json = """
    {"id":"00000000-0000-0000-0000-000000000001","localAudioReference":"clip.m4a","capturedAt":0,"device":"futureDevice","durationSeconds":2,"state":"futureState"}
    """
    let capture = try JSONDecoder().decode(MemoryCapture.self, from: Data(json.utf8))
    #expect(capture.device == .unknown)
    #expect(capture.state == .unknown)
}

@Test func memoryCaptureRejectsInvalidDurations() {
    let invalidValues = [-1.0, .nan, .infinity, -.infinity]
    for value in invalidValues {
        let capture = MemoryCapture(
            id: testUUID("000000000001"),
            localAudioReference: "clip.m4a",
            capturedAt: Date(timeIntervalSince1970: 0),
            device: .iPhone,
            durationSeconds: value,
            state: .captured
        )
        #expect(capture.durationSeconds == 0)
    }
}

@Test func memoryEventNormalizesBoundaries() {
    let sourceA = testUUID("000000000010")
    let sourceB = testUUID("000000000011")
    let inputTags = (0..<13).map { " tag" + String($0) + " " }
        + ["", "tag0"]
    let event = MemoryEvent(
        id: testUUID("000000000020"),
        occurredAt: Date(timeIntervalSince1970: 2_000),
        transcript: "  hello  ",
        importance: 140,
        tags: inputTags,
        sourceCaptureIDs: [sourceA, sourceA, sourceB]
    )
    #expect(event.transcript == "hello")
    #expect(event.importance == 100)
    #expect(event.tags == (0..<12).map { "tag" + String($0) })
    #expect(event.sourceCaptureIDs == [sourceA, sourceB])

    let low = MemoryEvent(
        id: testUUID("000000000021"),
        occurredAt: Date(timeIntervalSince1970: 2_001),
        transcript: "   ",
        importance: -1,
        tags: [],
        sourceCaptureIDs: []
    )
    #expect(low.transcript.isEmpty)
    #expect(low.importance == 0)
}

@Test func dailyMemoryDeduplicatesAndSortsStably() {
    let firstID = testUUID("000000000030")
    let secondID = testUUID("000000000031")
    let laterID = testUUID("000000000032")
    let first = makeEvent(id: firstID, time: 10)
    let second = makeEvent(id: secondID, time: 10)
    let later = makeEvent(id: laterID, time: 20)
    let duplicateFirst = makeEvent(id: firstID, time: 0)
    let daily = DailyMemory(
        id: testUUID("000000000040"),
        day: Date(timeIntervalSince1970: 0),
        events: [later, first, second, duplicateFirst]
    )
    #expect(daily.events.map { $0.id } == [firstID, secondID, laterID])
}

@Test func dailyMemoryRoundTripAndLegacyDefaults() throws {
    let daily = DailyMemory(
        id: testUUID("000000000040"),
        day: Date(timeIntervalSince1970: 0),
        events: [makeEvent(id: testUUID("000000000030"), time: 10)],
        isUserEdited: true
    )
    let data = try JSONEncoder().encode(daily)
    #expect(try JSONDecoder().decode(DailyMemory.self, from: data) == daily)

    let legacy = """
    {"id":"00000000-0000-0000-0000-000000000040","day":0}
    """
    let recovered = try JSONDecoder().decode(DailyMemory.self, from: Data(legacy.utf8))
    #expect(recovered.events.isEmpty)
    #expect(!recovered.isUserEdited)
}

@Test func dailyMemoryRequiresID() {
    let missingID = Data("{\"day\":0}".utf8)
    var didThrow = false
    do {
        _ = try JSONDecoder().decode(DailyMemory.self, from: missingID)
    } catch {
        didThrow = true
    }
    #expect(didThrow)
}

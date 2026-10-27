// Local Factory 課題 pm-watch-02 の見える試験と隠し試験(HarnessTasks/pm-watch-02)。
import Foundation
import Testing
@testable import SessionDomain
fileprivate let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func newPiecesAreSentAndRecentlySentOnesWait() {
    let a = UUID(), b = UUID(), c = UUID()
    let result = WatchDelivery.toSend(local: [a, b, c], outstanding: [], sentAt: [b: now.addingTimeInterval(-60)],
                                      now: now, resendAfter: 6 * 3600)
    #expect(result == [a, c])
}

@Test func piecesStillInTheQueueAreNotQueuedAgain() {
    let a = UUID(), b = UUID()
    #expect(WatchDelivery.toSend(local: [a, b], outstanding: [a], sentAt: [:], now: now, resendAfter: 3600) == [b])
}

@Test func onlyMatchingChecksumsMayBeDeleted() {
    let a = UUID(), b = UUID()
    let result = WatchDelivery.deletable(acknowledged: [a.uuidString: "aa", b.uuidString: "zz"],
                                         local: [a: "aa", b: "bb"])
    #expect(result == [a])
}

@Test func holdoutAPieceSentLongAgoWithoutAnAnswerIsSentAgain() {
    let a = UUID(), b = UUID()
    let result = WatchDelivery.toSend(local: [a, b], outstanding: [],
                                      sentAt: [a: now.addingTimeInterval(-3600), b: now.addingTimeInterval(-3599)],
                                      now: now, resendAfter: 3600)
    #expect(result == [a])
}

@Test func holdoutTheGivenOrderIsKept() {
    let ids = (0..<5).map { _ in UUID() }
    #expect(WatchDelivery.toSend(local: ids.reversed(), outstanding: [], sentAt: [:], now: now, resendAfter: 1) == ids.reversed())
}

@Test func holdoutUnknownOrMalformedAcknowledgementsDeleteNothing() {
    let a = UUID()
    let result = WatchDelivery.deletable(acknowledged: ["not-a-uuid": "aa", UUID().uuidString: "aa", a.uuidString: ""],
                                         local: [a: "aa"])
    #expect(result.isEmpty)
}

@Test func holdoutChecksumCaseDoesNotMatterAndLowercaseIDsAreRead() {
    let a = UUID(), b = UUID()
    let result = WatchDelivery.deletable(acknowledged: [a.uuidString.lowercased(): "ABCD", b.uuidString: "ef01"],
                                         local: [a: "abcd", b: "EF01"])
    #expect(result == [a, b].sorted { $0.uuidString < $1.uuidString })
}

@Test func holdoutAnEmptyLocalChecksumIsNeverDeleted() {
    let a = UUID()
    #expect(WatchDelivery.deletable(acknowledged: [a.uuidString: ""], local: [a: ""]).isEmpty)
}

@Test func holdoutAFutureSentTimeStillWaits() {
    let a = UUID()
    #expect(WatchDelivery.toSend(local: [a], outstanding: [], sentAt: [a: now.addingTimeInterval(600)], now: now, resendAfter: 60).isEmpty)
}

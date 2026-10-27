// Local Factory 課題 pm-watch-03 の見える試験と隠し試験(HarnessTasks/pm-watch-03)。
import Testing
@testable import SessionDomain
@Test func pressingSendsAndSaysHowMany() {
    let s = TransferSnapshot(onWatch: 6, queuedNow: 6, pressedByUser: true)
    #expect(TransferReport.headline(s) == "6件を送り始めました")
    #expect(TransferReport.detail(s) == "Watchに残っている録音: 6件")
}

@Test func nothingToSendSaysWhy() {
    let s = TransferSnapshot(onWatch: 3, pressedByUser: true)
    #expect(TransferReport.headline(s) == "3件がiPhoneの保存待ち")
    #expect(TransferReport.detail(s) == "Watchに残っている録音: 3件\n送ったものはiPhoneの確認を待っています。6時間たっても確認が無ければ送り直します。")
}

@Test func everythingSaved() {
    let s = TransferSnapshot(onWatch: 0, deletedSinceOpen: 46)
    #expect(TransferReport.headline(s) == "すべてiPhoneに保存済み")
    #expect(TransferReport.detail(s) == "iPhoneに保存を確かめてWatchから消した録音: 46件")
}

@Test func holdoutAFailureComesFirst() {
    let s = TransferSnapshot(onWatch: 2, queuedNow: 2, inFlight: 1, lastFailure: "iPhoneに接続できません", deletedSinceOpen: 1, pressedByUser: true)
    #expect(TransferReport.headline(s) == "送れませんでした")
    #expect(TransferReport.detail(s) == "理由: iPhoneに接続できません。1分後に送り直します。\nWatchに残っている録音: 2件\niPhoneに保存を確かめてWatchから消した録音: 1件")
}

@Test func holdoutABlankFailureIsNoFailure() {
    let s = TransferSnapshot(onWatch: 1, inFlight: 1, lastFailure: "   ")
    #expect(TransferReport.headline(s) == "1件を送信中")
    #expect(TransferReport.detail(s) == "Watchに残っている録音: 1件")
}

@Test func holdoutQueuedWinsOverInFlight() {
    #expect(TransferReport.headline(TransferSnapshot(onWatch: 5, queuedNow: 2, inFlight: 4)) == "2件を送り始めました")
}

@Test func holdoutTheWaitingNoteOnlyWhenPressedAndNothingMoves() {
    #expect(!TransferReport.detail(TransferSnapshot(onWatch: 3)).contains("6時間"))
    #expect(!TransferReport.detail(TransferSnapshot(onWatch: 3, inFlight: 1, pressedByUser: true)).contains("6時間"))
    #expect(!TransferReport.detail(TransferSnapshot(onWatch: 0, pressedByUser: true)).contains("6時間"))
}

@Test func holdoutNothingAtAllHasAnEmptyDetail() {
    #expect(TransferReport.headline(TransferSnapshot()) == "すべてiPhoneに保存済み")
    #expect(TransferReport.detail(TransferSnapshot()) == "")
}

@Test func holdoutNegativeCountsCountAsZero() {
    let s = TransferSnapshot(onWatch: -1, queuedNow: -2, inFlight: -3, deletedSinceOpen: -4)
    #expect(TransferReport.headline(s) == "すべてiPhoneに保存済み")
    #expect(TransferReport.detail(s) == "")
}

@Test func holdoutTheFailureTextIsTrimmed() {
    #expect(TransferReport.detail(TransferSnapshot(lastFailure: " 時間切れ \n")) == "理由: 時間切れ。1分後に送り直します。")
}

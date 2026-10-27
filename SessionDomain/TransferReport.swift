import Foundation

/// What the Watch shows after sending or pressing 「iPhoneへ再送」 (2026-10-27). Pressing it used to change nothing
/// visible, so the user could not tell whether it worked. Queued and delivered are different moments: a piece is
/// delivered only when the iPhone confirms it saved the same bytes and the Watch deletes it.
public struct TransferSnapshot: Equatable, Sendable {
    /// Finished pieces still on the Watch.
    public var onWatch: Int
    /// Pieces queued by this run.
    public var queuedNow: Int
    /// Transfers still in WatchConnectivity's queue.
    public var inFlight: Int
    /// The last transfer error, nil when none since the last success.
    public var lastFailure: String?
    /// Pieces the iPhone confirmed and the Watch deleted since the app opened.
    public var deletedSinceOpen: Int
    /// This run was the user pressing 「iPhoneへ再送」.
    public var pressedByUser: Bool

    public init(onWatch: Int = 0, queuedNow: Int = 0, inFlight: Int = 0, lastFailure: String? = nil,
                deletedSinceOpen: Int = 0, pressedByUser: Bool = false) {
        self.onWatch = onWatch; self.queuedNow = queuedNow; self.inFlight = inFlight; self.lastFailure = lastFailure
        self.deletedSinceOpen = deletedSinceOpen; self.pressedByUser = pressedByUser
    }
}

public enum TransferReport {
    /// One short line shown large.
    public static func headline(_ snapshot: TransferSnapshot) -> String {
        let onWatch = max(0, snapshot.onWatch)
        let queuedNow = max(0, snapshot.queuedNow)
        let inFlight = max(0, snapshot.inFlight)
        let failure = snapshot.lastFailure?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let failure, !failure.isEmpty { return "送れませんでした" }
        if onWatch == 0 { return "すべてiPhoneに保存済み" }
        if queuedNow > 0 { return "\(queuedNow)件を送り始めました" }
        if inFlight > 0 { return "\(inFlight)件を送信中" }
        return "\(onWatch)件がiPhoneの保存待ち"
    }

    /// The lines under it, joined with newlines.
    public static func detail(_ snapshot: TransferSnapshot) -> String {
        let onWatch = max(0, snapshot.onWatch)
        let queuedNow = max(0, snapshot.queuedNow)
        let inFlight = max(0, snapshot.inFlight)
        let deletedSinceOpen = max(0, snapshot.deletedSinceOpen)
        let failure = snapshot.lastFailure?.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        if let failure, !failure.isEmpty { lines.append("理由: \(failure)。1分後に送り直します。") }
        if onWatch > 0 { lines.append("Watchに残っている録音: \(onWatch)件") }
        if deletedSinceOpen > 0 { lines.append("iPhoneに保存を確かめてWatchから消した録音: \(deletedSinceOpen)件") }
        if snapshot.pressedByUser, (failure == nil || failure?.isEmpty == true), queuedNow == 0, inFlight == 0, onWatch > 0 {
            lines.append("送ったものはiPhoneの確認を待っています。6時間たっても確認が無ければ送り直します。")
        }
        return lines.joined(separator: "\n")
    }
}

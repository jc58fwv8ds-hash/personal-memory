import Foundation

/// What the Watch sends to the iPhone and what it may delete (2026-10-27). The Watch used to queue every recording it
/// held after each new piece, including ones already delivered, so a long day backed up for hours; and nothing was ever
/// deleted from the Watch. Now a delivered piece waits for the iPhone's acknowledgement, and only a piece the iPhone
/// saved with the same SHA-256 is deleted.
public enum WatchDelivery {
    /// The pieces to queue now, in the order of `local`.
    public static func toSend(local: [UUID], outstanding: Set<UUID>, sentAt: [UUID: Date], now: Date,
                              resendAfter: TimeInterval) -> [UUID] {
        local.filter { id in
            guard !outstanding.contains(id) else { return false }
            guard let sent = sentAt[id] else { return true }
            return sent <= now && now.timeIntervalSince(sent) >= resendAfter
        }
    }

    /// The pieces the iPhone acknowledged with the same checksum as this Watch's record, sorted by `uuidString`.
    public static func deletable(acknowledged: [String: String], local: [UUID: String]) -> [UUID] {
        var result: [UUID] = []
        for (key, ackSum) in acknowledged {
            guard let id = UUID(uuidString: key), let localSum = local[id], !localSum.isEmpty,
                  localSum.caseInsensitiveCompare(ackSum) == .orderedSame else { continue }
            result.append(id)
        }
        return result.sorted { $0.uuidString < $1.uuidString }
    }
}

#if canImport(WatchCaptureControl)
import Foundation
import Testing
@testable import WatchCaptureControl

struct RecordingCancellationTests {
    @Test func cancellationIsStickyAndNewRequestsAreIndependent() {
        let first = RecordingCancellation()
        #expect(!first.isCancelled)
        first.cancel()
        first.cancel()
        #expect(first.isCancelled)
        #expect(!RecordingCancellation().isCancelled)
    }

    @Test func cancellationDoesNotWaitForBusyWorker() {
        let token = RecordingCancellation()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue(label: "test.blocked-audio").async {
            entered.signal()
            _ = release.wait(timeout: .now() + 1)
            #expect(token.isCancelled)
            finished.signal()
        }
        defer { release.signal() }
        #expect(entered.wait(timeout: .now() + 1) == .success)
        token.cancel()
        #expect(token.isCancelled)
        release.signal()
        #expect(finished.wait(timeout: .now() + 1) == .success)
    }
}
#endif

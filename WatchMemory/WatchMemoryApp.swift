import SwiftUI

@main
struct WatchMemoryApp: App {
    var body: some Scene {
        WindowGroup { NavigationStack { WatchCaptureView() } }
    }
}

private struct WatchCaptureView: View {
    @StateObject private var recorder = WatchRecorder()
    @StateObject private var transfer = WatchTransfer()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("記憶を録音").font(.headline)
                if let directory = try? WatchRecorder.directory() {
                    NavigationLink {
                        RecordingsView(directory: directory, refreshToken: transfer.deletedCount)
                    } label: {
                        Label("録音を聴く", systemImage: "play.circle")
                    }
                    .disabled(recorder.isBusy || recorder.wantsRecording)
                    .accessibilityIdentifier("watch-recordings")
                }
                Text(recorder.status).font(.caption)
                Button(recorder.wantsRecording || recorder.isBusy ? "停止して残す" : "録音する") {
                    if recorder.wantsRecording || recorder.isBusy { recorder.stop() }
                    else { Task { await recorder.start() } }
                }
                .accessibilityIdentifier("watch-record")
                // 2026-10-27: the result of sending is a headline the user can see, with when it happened.
                if transfer.headline.isEmpty {
                    Text(transfer.status).font(.caption2)
                } else {
                    VStack(spacing: 2) {
                        Text(transfer.headline).font(.headline).multilineTextAlignment(.center)
                        if !transfer.detail.isEmpty { Text(transfer.detail).font(.caption2).multilineTextAlignment(.center) }
                        if let at = transfer.updatedAt { Text(at, style: .time).font(.caption2).foregroundStyle(.secondary) }
                    }
                    .accessibilityIdentifier("watch-transfer-report")
                }
                Button("iPhoneへ再送") { transfer.sendPending(pressedByUser: true) }
                    .accessibilityIdentifier("watch-send")
                Text("録音中は文字盤に戻っても続き、タイマーなどで中断されても自動で再開します。約10分ごとに保存し、iPhoneが同じ中身で保存したことを確かめてからWatchから消します。").font(.caption2)
            }
            .padding(.horizontal, 6)
        }
        .onChange(of: recorder.lastRecording) { _, _ in transfer.sendPending() }
    }
}

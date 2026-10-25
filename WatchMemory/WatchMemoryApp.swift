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
                        RecordingsView(directory: directory)
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
                Text(transfer.status).font(.caption2)
                Button("iPhoneへ再送") { transfer.sendPending() }
                    .disabled(recorder.isBusy)
                    .accessibilityIdentifier("watch-send")
                Text("録音中は文字盤に戻っても続き、タイマーなどで中断されても自動で再開します。約10分ごとに保存し、iPhoneに届いても原本はWatchに残ります。").font(.caption2)
            }
            .padding(.horizontal, 6)
        }
        .onChange(of: recorder.lastRecording) { _, _ in transfer.sendPending() }
    }
}

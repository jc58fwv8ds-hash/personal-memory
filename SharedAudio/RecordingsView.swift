import AVFoundation
import SwiftUI

struct RecordingsView: View {
    let directory: URL
    var refreshToken = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var items: [RecordingItem] = []
    @State private var loadError: String?
    @State private var loaded = false
    @StateObject private var player = RecordingPlayer()

    var body: some View {
        List {
            if let loadError {
                Section {
                    Text(loadError).foregroundStyle(.red)
                    Button("読み直す") { Task { await reload() } }
                }
            } else if !loaded {
                ProgressView("録音を読み込んでいます")
            } else if items.isEmpty {
                Section {
                    Label("録音はまだありません", systemImage: "waveform")
                    Text("Watchで録音すると、ここから聴き直せます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text(player.status).accessibilityIdentifier("playback-status")
                    if player.duration > 0 {
                        ProgressView(value: min(player.elapsed, player.duration), total: player.duration)
                        Text("\(player.elapsed, specifier: "%.0f")秒 / \(player.duration, specifier: "%.0f")秒")
                            .font(.caption).monospacedDigit()
                    }
                }
                Section("録音 \(items.count)件") {
                    ForEach(items) { item in
                        let active = player.isBusy && player.selectedID == item.id
                        Button {
                            if active { player.stop() } else { player.play(item) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.savedAt, format: .dateTime.month().day().hour().minute().second())
                                    Text(active ? "停止" : "再生").font(.caption)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: active ? "stop.fill" : "play.fill")
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .disabled(player.isBusy && !active)
                        .accessibilityIdentifier("play-recording-\(item.id.uuidString)")
#if os(iOS)
                        RecordingShareButton(item: item)
#endif
                    }
                }
                Section {
                    Text("保存した日時の新しい順です。原本は消しません。")
                        .font(.caption).foregroundStyle(.secondary)
#if os(iOS)
                    Text("「Macなどへ共有」でAirDropやファイル保存を選べます。Macへの自動中継・AI整理はまだ準備中です。")
                        .font(.caption).foregroundStyle(.secondary)
#endif
#if os(watchOS)
                    Text("音が出ない場合は音量・接続先を確認するか、iPhoneで聴いてください。")
                        .font(.caption2).foregroundStyle(.secondary)
#endif
                }
            }
        }
        .navigationTitle("録音")
        .task(id: refreshToken) { await reload() }
        .onDisappear { player.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            player.stop()
        }
    }

    private func reload() async {
        do {
            let directory = directory
            let recordings = try await Task.detached(priority: .utility) {
                try RecordingCatalog.recordings(in: directory)
            }.value
            try Task.checkCancellation()
            items = recordings
            loadError = nil
            loaded = true
        } catch is CancellationError {
            return
        } catch {
            loadError = "録音を読み込めませんでした。保存データは変更していません。"
        }
    }
}

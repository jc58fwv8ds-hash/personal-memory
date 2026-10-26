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
                // One row per day (2026-10-26): the Watch saves a piece every 10 minutes, but a person thinks in days.
                Section("日ごとの録音") {
                    ForEach(days, id: \.day) { day in
                        let active = player.isBusy && player.playingDay == day.day
                        Button {
                            if active { player.stop() } else { player.play(day: day.day, pieces: day.pieces) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(day.day, format: .dateTime.month().day().weekday())
                                        .font(.headline)
                                    Text(Self.summary(of: day)).font(.caption).foregroundStyle(.secondary)
                                    if active {
                                        Text("再生中 \(player.position + 1)/\(day.pieces.count)・"
                                             + (day.pieces[min(player.position, day.pieces.count - 1)].recordedAt
                                                .formatted(date: .omitted, time: .shortened)) + "の部分")
                                            .font(.caption)
                                    }
                                }
                                Spacer(minLength: 4)
                                Image(systemName: active ? "stop.fill" : "play.fill")
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .disabled(player.isBusy && !active)
                        .accessibilityIdentifier("play-day-\(Int(day.day.timeIntervalSince1970))")
                    }
                }
                Section {
                    Text("新しい日から並びます。押すとその日の録音を頭から続けて再生します。原本は消しません。")
                        .font(.caption).foregroundStyle(.secondary)
#if os(iOS)
                    Text("Macへは「Macと同期」で設定した共有フォルダから自動で届きます。文字起こしと整理はMacのアプリで行います。")
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

    private var days: [RecordingDay<RecordingItem>] {
        RecordingDays.group(items, calendar: .current, start: \.recordedAt, end: { $0.end ?? $0.recordedAt })
    }

    private static func summary(of day: RecordingDay<RecordingItem>) -> String {
        let span = day.start.formatted(date: .omitted, time: .shortened) + "〜" + day.end.formatted(date: .omitted, time: .shortened)
        let minutes = Int(day.seconds / 60)
        let length = minutes >= 60 ? "\(minutes / 60)時間\(minutes % 60)分" : "\(minutes)分"
        return day.seconds > 0 ? "\(span)・\(length)" : span
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

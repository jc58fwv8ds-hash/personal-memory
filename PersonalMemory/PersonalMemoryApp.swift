import SwiftUI
import UniformTypeIdentifiers

@main
struct PersonalMemoryApp: App {
    @StateObject private var watchReceiver = WatchCaptureReceiver()
    @StateObject private var nearbySender = NearbyChunkSender()
    @StateObject private var relay = RelayFolderSender()
    @State private var choosingFolder = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                .safeAreaInset(edge: .top) {
                    VStack(spacing: 2) {
                        Text(watchReceiver.status)
                        Text("iPhoneに保持した録音: \(watchReceiver.receivedCount)件")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
                    .accessibilityIdentifier("watch-receive-status")
                }
                .tabItem { Label("記憶", systemImage: "text.bubble") }
                NavigationStack {
                    if let directory = try? CaptureAudioInbox.defaultDirectory() {
                        RecordingsView(directory: directory, refreshToken: watchReceiver.receivedCount)
                    } else {
                        ContentUnavailableView("録音の保存先を開けません", systemImage: "exclamationmark.folder")
                    }
                }
                .tabItem { Label("録音", systemImage: "waveform") }
                NavigationStack {
                    Form {
                        Section("iCloud Driveのフォルダ経由(おすすめ)") {
                            LabeledContent("共有フォルダ", value: relay.folderName ?? "未設定")
                            Button(relay.folderName == nil ? "フォルダを選ぶ" : "フォルダを変える") { choosingFolder = true }
                            Button("今すぐ送る") { relay.sendPending() }.disabled(relay.folderName == nil)
                            Text(relay.status).font(.caption).foregroundStyle(.secondary)
                            Text("iCloud Driveに「Personal Memory」などのフォルダを作って選び、Macのアプリでも同じフォルダを選びます。Watchから届いた録音を自動で置き、原本はこのiPhoneに残ります。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Section("同じWi‑FiのMacに直接送る") {
                            Text(nearbySender.macName ?? "同じWi‑FiにあるMacを探しています")
                            TextField("Macに表示された6桁の番号", text: $nearbySender.pairingCode)
                                .keyboardType(.numberPad)
                            Button("Macへ接続") { nearbySender.connect() }
                                .disabled(nearbySender.macName == nil || nearbySender.pairingCode.count != 6)
                            Button("送信待ちの録音を送る") { nearbySender.sendPending() }
                            Label(nearbySender.phase.title, systemImage: nearbySender.phase.symbol)
                                .font(.headline)
                            Text(nearbySender.status).font(.caption).foregroundStyle(.secondary)
                            Text("Macへの送信後も録音はこのiPhoneに残ります。")
                        }
                    }
                    .navigationTitle("Macと同期")
                }
                .tabItem { Label("Macと同期", systemImage: "arrow.left.arrow.right") }
            }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                if case let .success(url) = result { relay.choose(url) }
            }
            .onChange(of: watchReceiver.receivedCount) { _, _ in relay.sendPending() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { relay.sendPending() } }
        }
    }
}

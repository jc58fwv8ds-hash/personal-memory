import SwiftUI
import AppKit

@main struct MemoryCalendarApp: App {
    @State private var session = CalendarSession()
    var body: some Scene {
        WindowGroup("Personal Memory") {
            CalendarWorkspaceView(session: session).frame(minWidth: 880, minHeight: 650)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }.defaultSize(width: 1040, height: 800)
    }
}

struct CalendarWorkspaceView: View {
    @Bindable var session: CalendarSession
    @State private var days = DayMemorySession()
    @State private var mode = Mode.days
    @State private var relay: RelayFolderWatcher?
    @State private var daySession: DaySession?
    enum Mode: String, CaseIterable { case days = "日ごと", day = "一日の記憶", calendar = "ファイルから" }
    @StateObject private var nearby = NearbyChunkReceiver(root: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/PersonalMemoryCalendar/ReceivedChunks"))
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "waveform.badge.plus").font(.system(size: 36)).foregroundStyle(.teal)
                Text("一日の録音を、\n予定とメモへ。").font(.largeTitle.weight(.semibold))
                Text("1  日付を選ぶ\n\n2  この日を文字起こし\n\n3  項目に分けて提案\n\n4  確かめて保存").foregroundStyle(.secondary)
                Spacer()
                Text("音声とAI処理はこのMac内。\n登録先のカレンダーは、そのアカウントの同期設定に従います。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(width: 240).frame(maxHeight: .infinity).background(.thinMaterial)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("画面", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 380)
                    if mode == .days {
                        if let daySession { DayListView(session: daySession, receiver: nearby, model: session.model) }
                        DisclosureGroup("iPhoneとの接続") {
                            if let relay { RelayFolderRow(watcher: relay) }
                            HStack {
                                Label("同じWi‑Fiで直接", systemImage: "iphone.gen3.radiowaves.left.and.right")
                                Spacer()
                                Text(nearby.pairingCode).monospacedDigit().fontWeight(.semibold)
                            }
                            Text("iPhoneの「Macと同期」にこの番号を入力すると直接送れます。" + nearby.status)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        DisclosureGroup("ローカルAIの設定") {
                            TextField("モデル", text: $session.model).textFieldStyle(.roundedBorder)
                            Text("Ollamaの127.0.0.1:11434だけに接続します。モデルがなければ自動ダウンロードせず停止します。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if mode == .day {
                        DayMemoryView(session: days, model: session.model)
                    } else {
                    HStack {
                        Text("Personal Memory").font(.title2.weight(.medium))
                        Spacer()
                        Button("録音を読み込む…", systemImage: "square.and.arrow.down") { session.chooseRecording() }
                            .disabled(session.busy || !session.storageHealthy)
                    }
                    Text(session.message).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .padding().background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    if session.busy { HStack { ProgressView().controlSize(.small); Button("中止") { session.cancel() } } }
                    if !session.storageHealthy { Button("変更の保存を再試行") { session.retryLocalSave() } }
                    if let doc = session.document {
                        Label("録音 \(doc.referenceDate.formatted(date: .abbreviated, time: .shortened))",
                              systemImage: "waveform").font(.headline)
                        HStack {
                            Button("録音を聴く", systemImage: "play.fill") { session.playRecording() }
                            Button("再生を止める") { session.stopPlayback() }
                        }.disabled(session.busy)
                        DatePicker("録音日時（「明日」の基準・要確認）", selection: Binding(
                            get: { doc.referenceDate }, set: { session.editReference($0) }))
                            .disabled(session.busy || !doc.submissions.isEmpty)
                        Text("タイムゾーン: \(doc.timeZoneID) · 受信ファイルの日時は録音時刻と違う場合があります。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("文字起こし").font(.headline)
                            Spacer()
                            Button("Mac内で文字起こし") { session.transcribe() }
                                .disabled(session.busy || !doc.submissions.isEmpty)
                        }
                        TextEditor(text: Binding(get: { doc.transcript }, set: { session.editTranscript($0) }))
                            .font(.body).frame(height: 150).padding(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                            .disabled(session.busy || !doc.submissions.isEmpty)
                        Text("15分以内の区切りを端末内で文字起こしします。言葉の境界や聞き違いを確認してください。文章や基準日時を変更すると、未登録の候補を作り直します。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("予定を提案", systemImage: "sparkles") { session.propose() }
                            .buttonStyle(.borderedProminent)
                            .disabled(session.busy || doc.transcript.isEmpty || !doc.submissions.isEmpty || !session.storageHealthy)
                        ForEach(doc.proposals) { draft in
                            ProposalCard(proposal: draft, submission: doc.submissions[draft.id], timeZoneID: doc.timeZoneID,
                                update: { session.editProposal($0) }, register: { session.pendingConfirmation = draft.id })
                                .disabled(session.busy || !session.storageHealthy)
                        }
                        if !doc.submissions.isEmpty {
                            Text("登録後の二重提案を防ぐため、この録音の再抽出は止めています。予定の変更・削除はカレンダーアプリで行えます。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        ContentUnavailableView("録音を予定につなげましょう", systemImage: "calendar.badge.clock",
                            description: Text("Mac上のm4aを1つずつ読み込めます。Watchの録音は「日ごと」にまとまっています。"))
                    }
                    DisclosureGroup("ローカルAIの設定") {
                        TextField("モデル", text: $session.model).textFieldStyle(.roundedBorder).disabled(session.busy)
                        Text("Ollamaの127.0.0.1:11434だけに接続します。モデルがなければ自動ダウンロードせず停止します。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    }
                }.padding(28)
            }
        }
        .alert("この予定をカレンダーに追加しますか？", isPresented: Binding(
            get: { session.pendingConfirmation != nil }, set: { if !$0 { session.pendingConfirmation = nil } }),
            presenting: session.pendingConfirmation) { id in
                Button("登録する") {
                    // Capture the presented ID, independent of SwiftUI's dismissal-binding order.
                    session.register(id)
                    session.pendingConfirmation = nil
                }
                Button("戻る", role: .cancel) { session.pendingConfirmation = nil }
            } message: { id in
                Text(confirmationSummary(id))
            }
        .onAppear {
            if relay == nil { relay = RelayFolderWatcher(receiver: nearby) }
            if daySession == nil { daySession = DaySession(receiver: nearby) }
        }
        // 2026-10-26: pieces arriving from the iPhone are no longer opened and transcribed one by one here;
        // they join their day in 日ごと, where the whole day is transcribed on request.
    }

    private func confirmationSummary(_ id: UUID) -> String {
        guard let doc = session.document, let draft = doc.proposals.first(where: { $0.id == id }),
              let start = draft.start, let end = draft.end else { return "予定を選び直してください。" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: doc.timeZoneID)
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return "\(draft.title)\n\(formatter.string(from: start)) 〜 \(formatter.string(from: end))\n\(doc.timeZoneID)\n\nmacOSの設定に従うカレンダーへ、この予定とメモを追加します。既存の予定は読み取りません。登録後の変更・削除はカレンダーアプリで行えます。"
    }
}

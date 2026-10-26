import SwiftUI
import CalendarDomain
import SessionDomain

/// The days the Watch recorded, one button each; the chosen day is transcribed, sorted and saved as a whole (2026-10-26).
struct DayListView: View {
    @Bindable var session: DaySession
    @ObservedObject var receiver: NearbyChunkReceiver
    let model: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if session.days.isEmpty {
                ContentUnavailableView("まだ録音が届いていません", systemImage: "applewatch",
                    description: Text("Watchで録音すると、iPhoneを通してこのMacに届き、日ごとにまとまります。下の「iPhoneとの接続」を確かめてください。"))
            } else {
                Text("録音した日").font(.headline)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(session.days, id: \.day) { day in
                            DayButton(day: day, transcribed: session.transcribedByDay[day.day] ?? 0,
                                      audioDeleted: session.audioDeleted(day), selected: session.selected == day.day) {
                                session.select(day.day)
                            }
                        }
                    }.padding(.vertical, 2)
                }.disabled(session.busy)
            }
            if let day = session.day {
                DayDetail(session: session, day: day, model: model)
            }
        }
        .onAppear {
            session.refreshCounts()
            if session.selected == nil, let newest = session.days.first { session.select(newest.day) }
        }
        .onChange(of: receiver.savedChunks.count) { _, _ in session.refreshCounts() }
    }
}

private struct DayButton: View {
    let day: RecordingDay<SessionChunkReceipt>
    let transcribed: Int
    let audioDeleted: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.day, format: .dateTime.month().day().weekday()).font(.headline)
                Text(span).font(.caption).monospacedDigit().lineLimit(1)
                Text(length).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Label(status, systemImage: transcribed >= day.pieces.count ? "checkmark.circle.fill" : "waveform")
                    .font(.caption).foregroundStyle(transcribed >= day.pieces.count ? .green : .secondary)
            }
            .frame(width: 160, alignment: .leading).padding(12)
            .background(selected ? Color.teal.opacity(0.18) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.teal : .clear, lineWidth: 2))
        }.buttonStyle(.plain)
    }

    private var span: String {
        day.start.formatted(date: .omitted, time: .shortened) + "〜" + day.end.formatted(date: .omitted, time: .shortened)
    }

    private var length: String {
        let minutes = Int(day.seconds / 60)
        return "録音 " + (minutes >= 60 ? "\(minutes / 60)時間\(minutes % 60)分" : "\(minutes)分")
    }

    private var status: String {
        if transcribed >= day.pieces.count { return audioDeleted ? "文字起こし済み・音声削除" : "文字起こし済み" }
        return transcribed == 0 ? "未文字起こし" : "文字起こし \(transcribed * 100 / max(day.pieces.count, 1))%"
    }
}

private struct DayDetail: View {
    @Bindable var session: DaySession
    let day: RecordingDay<SessionChunkReceipt>
    let model: String
    @State private var showDismissed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(day.day, format: .dateTime.year().month().day().weekday()).font(.title2.weight(.medium))
            HStack(spacing: 10) {
                Button("この日を文字起こし", systemImage: "text.word.spacing") { session.transcribeDay() }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.busy || session.audioDeleted(day))
                Button("項目に分けて提案", systemImage: "sparkles") { session.suggest(model: model) }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.busy || session.transcriptText.isEmpty)
                if session.busy {
                    ProgressView().controlSize(.small)
                    Button("止める") { session.cancel() }
                }
            }
            if let progress = session.progress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
            }
            Text(session.message).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .padding().background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            if !session.transcriptText.isEmpty {
                DisclosureGroup("この日の文字起こし") {
                    ScrollView {
                        Text(session.transcriptText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 220).padding(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }
            }
            let open = session.suggestions.filter { $0.state != .dismissed }
            if !open.isEmpty { Text("保存の候補").font(.headline) }
            ForEach(open) { item in
                SuggestionCard(item: item, update: { session.edit($0) }, save: { session.pendingSave = item.id },
                               dismiss: { session.dismiss(item.id) })
                    .disabled(session.busy)
            }
            let dismissed = session.suggestions.filter { $0.state == .dismissed }
            if !dismissed.isEmpty {
                DisclosureGroup("不要にした候補(\(dismissed.count)件)", isExpanded: $showDismissed) {
                    ForEach(dismissed) { item in
                        HStack {
                            Text(item.title).foregroundStyle(.secondary)
                            Spacer()
                            Button("戻す") { session.restore(item.id) }
                        }
                    }
                }
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("この日の音声").font(.headline)
                    Text(session.audioDeleted(day) ? "このMacからは削除済みです(文字起こしと候補は残っています)。"
                         : "文字起こしの後は、音声をこのMacから削除できます。iPhoneと共有フォルダの原本は残ります。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("この日の音声を削除…", systemImage: "trash", role: .destructive) { session.confirmingDelete = true }
                    .disabled(session.busy || session.audioDeleted(day))
            }
        }
        .alert(saveTitle, isPresented: Binding(get: { session.pendingSave != nil }, set: { if !$0 { session.pendingSave = nil } }),
               presenting: session.pendingSave) { id in
            Button("保存する") { session.save(id); session.pendingSave = nil }
            Button("戻る", role: .cancel) { session.pendingSave = nil }
        } message: { id in
            Text(saveSummary(id))
        }
        .alert("この日の音声を削除しますか?", isPresented: $session.confirmingDelete) {
            Button("ゴミ箱に移す", role: .destructive) { session.deleteAudio() }
            Button("やめる", role: .cancel) {}
        } message: {
            let left = day.pieces.count - (session.transcribedByDay[day.day] ?? 0)
            Text((left > 0 ? "まだ文字起こししていない録音が\(left)件あります。削除すると、このMacでは文字起こしできなくなります。\n\n" : "")
                 + "このMacにある\(day.day.formatted(date: .abbreviated, time: .omitted))の音声をゴミ箱に移します。文字起こしと候補は残ります。iPhoneと共有フォルダの原本は消しません。")
        }
    }

    private var saveTitle: String {
        session.suggestions.first { $0.id == session.pendingSave }?.kind == .calendar ? "カレンダーに保存しますか?" : "メモに保存しますか?"
    }

    private func saveSummary(_ id: UUID) -> String {
        guard let item = session.suggestions.first(where: { $0.id == id }) else { return "" }
        if item.kind == .calendar, let start = item.start, let end = item.end {
            return "\(item.title)\n\(start.formatted(date: .abbreviated, time: .shortened)) 〜 \(end.formatted(date: .omitted, time: .shortened))\n\nmacOSの設定に従うカレンダーに追加します。既存の予定は読み取りません。"
        }
        return "\(item.title)\n\n「メモ」アプリに新しいメモを1つ作ります。既存のメモは読み取らず、変更もしません。初回はmacOSが操作の許可を確認します。"
    }
}

private struct SuggestionCard: View {
    let item: ItemSuggestion
    let update: (ItemSuggestion) -> Void
    let save: () -> Void
    let dismiss: () -> Void

    private func field(_ path: WritableKeyPath<ItemSuggestion, String>) -> Binding<String> {
        Binding(get: { item[keyPath: path] }, set: { var edited = item; edited[keyPath: path] = $0; update(edited) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("保存先", selection: Binding(get: { item.kind }, set: { kind in
                    var edited = item; edited.kind = kind
                    if kind == .memo { edited.start = nil; edited.end = nil }
                    update(edited)
                })) {
                    Label("カレンダー", systemImage: "calendar").tag(ItemSuggestion.Kind.calendar)
                    Label("メモ", systemImage: "note.text").tag(ItemSuggestion.Kind.memo)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
                Spacer()
                switch item.state {
                case .saved: Label("保存済み", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .saving: Label("保存できたか確かめてください(二重保存を防ぐため止めています)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.caption)
                default: EmptyView()
                }
            }
            TextField("件名", text: field(\.title)).font(.title3.weight(.semibold))
            TextField("内容", text: field(\.body), axis: .vertical).lineLimit(1...4)
            Label(item.sourceQuote, systemImage: "quote.bubble").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if item.kind == .calendar {
                if let start = item.start, let end = item.end {
                    HStack {
                        DatePicker("開始", selection: Binding(get: { start }, set: { var e = item; e.start = $0; update(e) }))
                        DatePicker("終了", selection: Binding(get: { end }, set: { var e = item; e.end = $0; update(e) }))
                    }
                } else {
                    HStack {
                        Label("録音では日時がはっきりしませんでした。", systemImage: "questionmark.circle").foregroundStyle(.orange)
                        Button("日時を入れる") {
                            var edited = item
                            let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date()
                            edited.start = next; edited.end = next.addingTimeInterval(3600); update(edited)
                        }
                    }
                }
            }
            if item.state == .suggested {
                HStack {
                    Button("不要", action: dismiss)
                    Spacer()
                    Button(item.kind == .calendar ? "カレンダーに保存…" : "メモに保存…", action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty
                                  || (item.kind == .calendar && (item.start == nil || item.end == nil || item.end! <= item.start!)))
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
        .disabled(item.state != .suggested)
    }
}

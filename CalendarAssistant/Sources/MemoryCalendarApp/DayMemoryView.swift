import SwiftUI
import CalendarDomain

/// The day's memory: pick a day, summarize its recordings, then read and correct the moments.
struct DayMemoryView: View {
    @Bindable var session: DayMemorySession
    let model: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                DatePicker("日付", selection: $session.day, displayedComponents: .date).fixedSize()
                    .disabled(session.busy)
                Spacer()
                if session.busy {
                    ProgressView().controlSize(.small)
                    Button("中止") { session.cancel() }
                }
                Button("一日の記憶にまとめる", systemImage: "sparkles") { session.summarize(model: model) }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.busy || !session.healthy || session.transcribedCount == 0)
            }
            Text(session.message).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .padding().background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            if session.recordings.count > session.transcribedCount {
                Text("文字起こしがまだの録音は、「予定」の画面で文字起こしするとまとめに入ります。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if session.moments.isEmpty {
                ContentUnavailableView("まだ記憶がありません", systemImage: "book.closed",
                    description: Text("その日の録音を文字起こししてから、まとめてください。"))
            }
            ForEach(session.moments) { moment in
                MomentRow(moment: moment, update: { session.edit($0) }, delete: { session.delete(moment.id) })
                    .disabled(session.busy || !session.healthy)
            }
        }
        .onAppear { session.reload() }
        .onChange(of: session.day) { _, _ in session.reload() }
    }
}

private struct MomentRow: View {
    let moment: DayMoment
    let update: (DayMoment) -> Void
    let delete: () -> Void
    @State private var summary = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(moment.occurredAt.formatted(date: .omitted, time: .shortened)).monospacedDigit().font(.headline)
                ForEach(moment.tags, id: \.self) { Text($0).font(.caption).padding(.horizontal, 6).background(.quaternary, in: Capsule()) }
                Spacer()
                if moment.userEdited { Label("自分で修正", systemImage: "pencil").font(.caption).foregroundStyle(.secondary) }
                Button("削除", systemImage: "trash", role: .destructive, action: delete).labelStyle(.iconOnly)
            }
            TextField("要約", text: $summary, axis: .vertical).textFieldStyle(.roundedBorder)
                .onSubmit { commit() }
            Text("「\(moment.sourceQuote)」").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(12).background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .onAppear { summary = moment.summary }
        .onChange(of: moment.summary) { _, value in summary = value }
        .onDisappear { commit() }
    }

    private func commit() {
        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 300, text != moment.summary else { return }
        var changed = moment
        changed.summary = text
        update(changed)
    }
}

import SwiftUI
import CalendarDomain

struct ProposalCard: View {
    let proposal: CalendarProposal
    let submission: String?
    let timeZoneID: String
    let update: (CalendarProposal) -> Void
    let register: () -> Void

    private func field<T>(_ path: WritableKeyPath<CalendarProposal, T>) -> Binding<T> {
        Binding(get: { proposal[keyPath: path] }, set: { value in
            var edited = proposal; edited[keyPath: path] = value
            edited.dateConfirmed = false; update(edited)
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("予定の名前", text: field(\.title)).font(.title3.weight(.semibold))
            Label(proposal.sourceQuote, systemImage: "quote.bubble").foregroundStyle(.secondary).textSelection(.enabled)
            if let start = proposal.start, let end = proposal.end {
                HStack {
                    DatePicker("開始", selection: Binding(get: { start }, set: { value in
                        var edited = proposal; edited.start = value; edited.dateConfirmed = false; update(edited)
                    }))
                    DatePicker("終了", selection: Binding(get: { end }, set: { value in
                        var edited = proposal; edited.end = value; edited.dateConfirmed = false; update(edited)
                    }))
                }
                .environment(\.timeZone, TimeZone(identifier: timeZoneID) ?? .current)
            } else {
                Label("日時は未確定です。日付のないタスクも、ここで予定にできます。", systemImage: "questionmark.circle")
                    .foregroundStyle(.orange)
                Button("日時を指定する") {
                    var edited = proposal
                    edited.start = Date(); edited.end = Date().addingTimeInterval(3600)
                    edited.dateConfirmed = false; update(edited)
                }
            }
            TextField("メモ・確認したいこと", text: field(\.notes), axis: .vertical).lineLimit(2...5)
            if let submission {
                Label(submission.hasPrefix("saved:") ? "登録済み" : "登録結果を確認してください。二重登録を防ぐため再実行を止めています。",
                      systemImage: submission.hasPrefix("saved:") ? "checkmark.circle.fill" : "exclamationmark.triangle")
            } else {
                Toggle("件名と日時を確認しました", isOn: Binding(get: { proposal.dateConfirmed }, set: { value in
                    var edited = proposal; edited.dateConfirmed = value; update(edited)
                }))
                HStack {
                    Text(timeZoneID).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("この予定を登録…", action: register).buttonStyle(.borderedProminent)
                        .disabled(!proposal.canRegister)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(18).background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
        .disabled(submission != nil)
    }
}

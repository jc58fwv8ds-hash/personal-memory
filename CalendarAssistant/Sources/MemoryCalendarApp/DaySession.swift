import Foundation
import Observation
import CalendarDomain
import SessionDomain

/// One recorded day on this Mac (2026-10-26): the Watch's 10-minute pieces are shown and handled as the day they belong to.
/// Transcribe the whole day (resumable, piece by piece), let the local model sort it into calendar events and memos,
/// save the ones the user confirms, and optionally delete the day's audio from this Mac.
@MainActor @Observable final class DaySession {
    var selected: Date?
    private(set) var transcript = DayTranscript()
    private(set) var suggestions: [ItemSuggestion] = []
    /// Transcribed pieces per day, for the day buttons.
    private(set) var transcribedByDay: [Date: Int] = [:]
    var message = "日付を押すと、その日の録音をまとめて扱えます。"
    private(set) var busy = false
    private(set) var progress: (done: Int, total: Int)?
    var pendingSave: UUID?
    var confirmingDelete = false
    private var operation: Task<Void, Never>?
    private let transcripts: DayTranscriptBook
    private let suggestionBook: DaySuggestionBook
    private let transcriber = FileTranscriber()
    private let calendarWriter = CalendarWriter()
    private let notes = NotesWriter()
    private let recordings: RecordingWorkspace
    let receiver: NearbyChunkReceiver

    init(receiver: NearbyChunkReceiver) {
        self.receiver = receiver
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PersonalMemoryCalendar")
        transcripts = DayTranscriptBook(directory: base.appendingPathComponent("DayTranscripts"), calendar: .current)
        suggestionBook = DaySuggestionBook(directory: base.appendingPathComponent("DaySuggestions"), calendar: .current)
        recordings = RecordingWorkspace(root: base.appendingPathComponent("Recordings"))
    }

    var days: [RecordingDay<SessionChunkReceipt>] {
        RecordingDays.group(receiver.savedChunks, calendar: .current, start: \.start, end: \.end)
    }

    var day: RecordingDay<SessionChunkReceipt>? { days.first { $0.day == selected } }

    var transcriptText: String { DayTranscriptBook.text(of: transcript, timeZone: .current) }

    func audioDeleted(_ day: RecordingDay<SessionChunkReceipt>) -> Bool {
        day.pieces.allSatisfy { receiver.isRetired($0.chunkID) }
    }

    func refreshCounts() {
        for day in days {
            transcribedByDay[day.day] = (try? transcripts.load(day: day.day))
                .map { saved in day.pieces.filter { saved.pieces[$0.chunkID.uuidString] != nil }.count } ?? 0
        }
    }

    func select(_ day: Date) {
        guard !busy else { return }
        selected = day
        do {
            transcript = try transcripts.load(day: day)
            suggestions = try suggestionBook.load(day: day)
            message = suggestions.isEmpty ? "「この日を文字起こし」を押すと、この日の録音をすべてMac内で文字起こしします。"
                : "保存したい項目を確かめて、カレンダーかメモに保存してください。"
        } catch {
            transcript = DayTranscript(); suggestions = []
            message = "この日の記録を読み込めません。上書きせずに止めています。\(error.localizedDescription)"
        }
    }

    /// Transcribes every piece of the day that has no text yet. Stopping keeps what was done; pressing again continues.
    func transcribeDay() {
        guard let day else { return }
        let pieces = day.pieces.filter { !receiver.isRetired($0.chunkID) }
        run { [self] in
            let missing = Set(try transcripts.missing(pieces.map(\.chunkID), day: day.day))
            let todo = pieces.filter { missing.contains($0.chunkID) }
            guard !todo.isEmpty else { message = "この日の録音はすべて文字起こし済みです。"; return }
            var failed = 0
            let began = Date()
            for (index, piece) in todo.enumerated() {
                try Task.checkCancellation()
                progress = (index, todo.count)
                let left = index == 0 ? "" : "・残り約\(Int(Date().timeIntervalSince(began) / Double(index) * Double(todo.count - index) / 60) + 1)分"
                message = "Mac内で文字起こししています(\(index + 1)/\(todo.count)\(left))。録音は外部へ送りません。"
                do {
                    let text = try await transcriber.transcribe(receiver.audioURL(for: piece))
                    transcript = try transcripts.record(Self.clockLines(text, start: piece.start), piece: piece.chunkID,
                                                        start: piece.start, day: day.day)
                } catch is CancellationError { throw CancellationError() }
                catch { failed += 1 }
            }
            refreshCounts()
            message = failed == 0 ? "この日の文字起こしができました。「項目に分けて提案」を押すと、カレンダーとメモの候補を作ります。"
                : "\(todo.count - failed)件を文字起こしし、\(failed)件はできませんでした。もう一度押すと残りだけやり直します。"
        }
    }

    /// The local model sorts the day's transcript into calendar events and memos, an hour or so at a time.
    func suggest(model: String) {
        guard let day else { return }
        let batches = LocalItemService.batches(of: transcriptText)
        guard !batches.isEmpty else { message = "文字起こしされた言葉がありません。先に文字起こししてください。"; return }
        run { [self] in
            var added = 0, skipped = 0, failed = 0
            for (index, batch) in batches.enumerated() {
                try Task.checkCancellation()
                progress = (index, batches.count)
                message = "ローカルAIが項目に分けています(\(index + 1)/\(batches.count))。このMacの外には送りません。"
                do {
                    let decoded = try await LocalItemService().suggestions(in: batch, day: day.day,
                        timeZoneID: TimeZone.current.identifier, model: model)
                    let before = suggestions.count
                    suggestions = try suggestionBook.merge(decoded.items, day: day.day)
                    added += suggestions.count - before; skipped += decoded.skipped
                } catch is CancellationError { throw CancellationError() }
                catch { failed += 1 }
            }
            message = "\(added)件の候補を足しました。" + (skipped > 0 ? "原文と合わない\(skipped)件は除きました。" : "")
                + (failed > 0 ? "\(failed)回分はAIの答えを使えませんでした。もう一度押せます。" : "")
                + "不要にしたものと保存したものは、やり直しても戻りません。"
        }
    }

    func edit(_ item: ItemSuggestion) {
        guard !busy, let saved = suggestions.first(where: { $0.id == item.id }), saved.state == .suggested else { return }
        persist(item)
    }

    func dismiss(_ id: UUID) {
        guard var item = suggestions.first(where: { $0.id == id }), item.state == .suggested else { return }
        item.state = .dismissed
        persist(item)
    }

    func restore(_ id: UUID) {
        guard var item = suggestions.first(where: { $0.id == id }), item.state == .dismissed else { return }
        item.state = .suggested
        persist(item)
    }

    /// Saves one confirmed suggestion to Calendar or Notes. `.saving` is written first: if the app stops in between,
    /// the item is left for the user to check instead of being saved twice.
    func save(_ id: UUID) {
        guard let day, let item = suggestions.first(where: { $0.id == id }), item.state == .suggested else { return }
        run { [self] in
            let quote = "録音(\(day.day.formatted(date: .abbreviated, time: .omitted)))より:「\(item.sourceQuote)」"
            if item.kind == .calendar {
                guard let start = item.start, let end = item.end, end > start else {
                    throw CalendarFlowError.message("開始と終了の日時を入れてから保存してください。")
                }
                try await calendarWriter.authorize()
                try mark(item, .saving)
                do {
                    _ = try calendarWriter.save(CalendarProposal(title: item.title, sourceQuote: item.sourceQuote, start: start, end: end,
                        notes: [item.body, quote].filter { !$0.isEmpty }.joined(separator: "\n\n"), dateConfirmed: true),
                        timeZoneID: TimeZone.current.identifier)
                } catch { try mark(item, .suggested); throw error }
                try mark(item, .saved)
                message = "「\(item.title)」をカレンダーに保存しました。"
            } else {
                try mark(item, .saving)
                do { _ = try notes.save(title: item.title, body: [item.body, quote].filter { !$0.isEmpty }.joined(separator: "\n\n")) }
                catch { try mark(item, .suggested); throw error }
                try mark(item, .saved)
                message = "「\(item.title)」をメモに保存しました。"
            }
        }
    }

    /// Moves the day's audio on this Mac to the Trash. Transcript, suggestions and receipts stay; the iPhone and the
    /// shared folder keep their copies.
    func deleteAudio() {
        guard let day else { return }
        run { [self] in
            let ids = Set(day.pieces.map(\.chunkID))
            let moved = try receiver.retireAudio(of: ids)
            // The older single-recording screen may have kept its own copy of these pieces.
            for hash in Set(day.pieces.map(\.recordingHash)) {
                if let copy = try? recordings.audioURL(hash), FileManager.default.fileExists(atPath: copy.path) {
                    try FileManager.default.trashItem(at: copy, resultingItemURL: nil)
                }
            }
            message = "この日の音声\(moved)件をゴミ箱に移しました。文字起こしと候補は残っています。ゴミ箱を空にするまでは戻せます。"
        }
    }

    func cancel() { operation?.cancel() }

    /// The transcriber marks each section with its offset ("[3:20] …"); the day reads better in clock time ("[08:48] …").
    /// The first section's mark is dropped: the day's text already starts the piece with its start time.
    static func clockLines(_ text: String, start: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "HH:mm"
        let lines = text.split(separator: "\n").enumerated().map { index, line -> String in
            guard let match = line.firstMatch(of: #/^\[(\d+):(\d\d)\] /#), let minutes = Int(match.1), let seconds = Int(match.2)
            else { return String(line) }
            let rest = line[match.range.upperBound...]
            return index == 0 ? String(rest) : "[\(format.string(from: start.addingTimeInterval(Double(minutes * 60 + seconds))))] " + rest
        }
        return lines.joined(separator: "\n")
    }

    private func mark(_ item: ItemSuggestion, _ state: ItemSuggestion.State) throws {
        guard let day else { return }
        var changed = item
        changed.state = state
        suggestions = try suggestionBook.update(changed, day: day.day)
    }

    private func persist(_ item: ItemSuggestion) {
        guard let day else { return }
        do { suggestions = try suggestionBook.update(item, day: day.day) }
        catch { message = "変更を保存できませんでした。\(error.localizedDescription)" }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        operation = Task { [self] in
            defer { busy = false; progress = nil; operation = nil }
            do { try await action() }
            catch is CancellationError { message = "止めました。ここまでの結果は残っています。もう一度押すと続きから行います。" }
            catch { message = error.localizedDescription }
        }
    }
}

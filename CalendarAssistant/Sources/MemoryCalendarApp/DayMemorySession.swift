import Foundation
import Observation
import CalendarDomain

/// The day's memory on this Mac: the day's transcribed recordings are summarized one by one into moments the user can
/// read, correct and delete. A new summary never replaces a moment the user corrected (DayMemoryBook).
@MainActor @Observable final class DayMemorySession {
    var day = Date()
    var moments: [DayMoment] = []
    var recordings: [CalendarDocument] = []
    var message = "日付を選び、その日の録音を記憶にまとめます。"
    var busy = false
    private(set) var healthy = true
    private var operation: Task<Void, Never>?
    private let workspace: RecordingWorkspace
    private let book: DayMemoryBook

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PersonalMemoryCalendar")
        workspace = RecordingWorkspace(root: base.appendingPathComponent("Recordings"))
        book = DayMemoryBook(directory: base.appendingPathComponent("Days"), calendar: .current)
    }

    var transcribedCount: Int { recordings.filter { !$0.transcript.isEmpty }.count }

    func reload() {
        do {
            recordings = try workspace.documents(onDayOf: day, calendar: .current)
            moments = try book.load(day: day)
            healthy = true
            message = recordings.isEmpty ? "この日の録音はまだありません。"
                : "この日の録音 \(recordings.count)件(文字起こし済み \(transcribedCount)件)。"
        } catch {
            healthy = false; moments = []
            message = "この日の記憶を読み込めません。上書きせずに止めています。\(error.localizedDescription)"
        }
    }

    func summarize(model: String) {
        let sources = recordings.filter { !$0.transcript.isEmpty }
        guard healthy, !busy, !sources.isEmpty else { return }
        busy = true
        operation = Task { [self] in
            defer { busy = false; operation = nil }
            var done = 0, failed = 0
            for document in sources {
                if Task.isCancelled { break }
                message = "ローカルAIが録音をまとめています(\(done + failed + 1)/\(sources.count))。このMacの外には送りません。"
                do {
                    let new = try await LocalDayMemoryService().moments(of: DayRecording(document),
                        timeZoneID: document.timeZoneID, model: model)
                    moments = try book.merge(new, day: day)
                    done += 1
                } catch is CancellationError { break }
                catch { failed += 1 }
            }
            message = failed == 0 ? "\(done)件の録音を記憶にまとめました。自分で直した項目はそのまま残ります。"
                : "\(done)件をまとめ、\(failed)件はAIの答えを確かめられず保存しませんでした。もう一度試せます。"
        }
    }

    func edit(_ moment: DayMoment) {
        guard healthy, !busy, let index = moments.firstIndex(where: { $0.id == moment.id }) else { return }
        var changed = moment
        changed.userEdited = true
        var next = moments
        next[index] = changed
        persist(next)
    }

    func delete(_ id: UUID) {
        guard healthy, !busy else { return }
        persist(moments.filter { $0.id != id })
    }

    func cancel() { operation?.cancel() }

    private func persist(_ next: [DayMoment]) {
        do { try book.save(next, day: day); moments = next }
        catch { message = "変更を保存できませんでした。\(error.localizedDescription)" }
    }
}

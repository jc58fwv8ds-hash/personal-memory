import AppKit
import Observation
import CalendarDomain
import UniformTypeIdentifiers
import AVFoundation

@MainActor @Observable final class CalendarSession {
    var document: CalendarDocument?
    var model = LocalProposalService.defaultModel
    var message = "iPhoneと接続して録音を受け取るか、Mac上のm4aを読み込めます。"
    var busy = false
    var pendingConfirmation: UUID?
    var storageHealthy = true
    private var operation: Task<Void, Never>?
    private let transcriber = FileTranscriber()
    private let calendar = CalendarWriter()
    private let workspace: RecordingWorkspace
    private var player: AVAudioPlayer?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        workspace = RecordingWorkspace(root: base.appendingPathComponent("PersonalMemoryCalendar/Recordings"))
    }
    func chooseRecording() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Audio]; panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run("録音をMacに保存しています。原本は変更しません。") { [self] in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let workspace = workspace
            let imported = try await Task.detached { try workspace.importRecording(url) }.value
            document = imported; storageHealthy = true
            message = "録音をMacに保存しました。「明日」などの基準になる録音日時を確認してください。"
        }
    }
    func receiveVerifiedChunk(_ url: URL, startedAt: Date) {
        run("iPhoneから届いた録音を開いています。") { [self] in
            let workspace = workspace
            var imported = try await Task.detached { try workspace.importRecording(url) }.value
            imported.referenceDate = startedAt
            try workspace.save(imported)
            document = imported; storageHealthy = true
            message = "録音を保存しました。Mac内で文字起こししています。"
            let text = try await transcriber.transcribe(workspace.audioURL(imported.recordingHash))
            document?.transcript = text
            try persist()
            message = "文字起こしができました。言葉と日時を確認してください。"
        }
    }
    func transcribe() {
        guard let doc = document, doc.submissions.isEmpty else { return }
        run("Mac内で文字起こししています。録音は外部へ送信しません。") { [self] in
            let text = try await transcriber.transcribe(workspace.audioURL(doc.recordingHash))
            document?.transcript = text; document?.proposals = []
            try persist()
            message = "文字起こしができました。聞き違いを直してから「予定を提案」を押してください。"
        }
    }
    func playRecording() {
        guard let document else { return }
        do {
            player?.stop()
            player = try AVAudioPlayer(contentsOf: workspace.audioURL(document.recordingHash))
            guard player?.play() == true else { throw CalendarFlowError.message("この録音を再生できませんでした。") }
        } catch { message = error.localizedDescription }
    }
    func stopPlayback() { player?.stop(); player = nil }
    func propose() {
        guard let doc = document, doc.submissions.isEmpty else { return }
        run("ローカルAIが予定の候補を考えています。カレンダーにはまだ登録しません。") { [self] in
            let drafts = try await LocalProposalService().propose(transcript: doc.transcript,
                reference: doc.referenceDate, timeZoneID: doc.timeZoneID, model: model)
            try Task.checkCancellation()
            document?.proposals = drafts
            try persist()
            message = drafts.isEmpty ? "予定の候補はありませんでした。必要なら文章を補って再提案できます。"
                : "\(drafts.count)件の候補があります。元の発言と日時を確認してください。登録は1件ずつ行います。"
        }
    }
    func editTranscript(_ value: String) {
        guard !busy, document?.submissions.isEmpty == true else { return }
        document?.transcript = value; document?.proposals = []
        saveOrReport()
    }
    func editReference(_ value: Date) {
        guard !busy, document?.submissions.isEmpty == true else { return }
        document?.referenceDate = value; document?.proposals = []
        saveOrReport()
    }
    func editProposal(_ value: CalendarProposal) {
        guard !busy, document?.submissions[value.id] == nil,
              let index = document?.proposals.firstIndex(where: { $0.id == value.id }) else { return }
        document?.proposals[index] = value
        saveOrReport()
    }
    func register(_ id: UUID) {
        guard storageHealthy, let doc = document, doc.submissions[id] == nil,
              let draft = doc.proposals.first(where: { $0.id == id }), draft.canRegister else { return }
        run("確認した予定をカレンダーへ登録しています。") { [self] in
            try await calendar.authorize()
            try Task.checkCancellation()
            document?.submissions[id] = "uncertain"
            try persist() // Failure here means NO calendar call.
            let identifier = try calendar.save(draft, timeZoneID: doc.timeZoneID)
            document?.submissions[id] = "saved:\(identifier)"
            do { try persist() } catch {
                document?.submissions[id] = "uncertain"
                throw CalendarFlowError.message("登録は実行されましたが記録の保存に失敗しました。再登録せずカレンダーで確認してください。")
            }
            message = "「\(draft.title)」を登録しました。カレンダーアプリで確認できます。"
        }
    }
    func cancel() { operation?.cancel() }
    func retryLocalSave() { saveOrReport() }
    private func persist() throws {
        guard let document else { return }
        do { try workspace.save(document); storageHealthy = true }
        catch { storageHealthy = false; throw error }
    }
    private func saveOrReport() {
        do { try persist() } catch { message = "変更を保存できません。登録を停止しています。\(error.localizedDescription)" }
    }
    private func run(_ status: String, action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        stopPlayback()
        busy = true; message = status
        operation = Task { [self] in
            defer { busy = false; operation = nil }
            do { try await action() }
            catch is CancellationError { message = "処理を中止しました。録音の原本は保持しています。" }
            catch { message = "処理を完了できませんでした。\(error.localizedDescription)" }
        }
    }
}

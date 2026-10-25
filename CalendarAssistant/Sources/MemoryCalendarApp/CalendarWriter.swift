import EventKit
import CalendarDomain

@MainActor final class CalendarWriter {
    private let store = EKEventStore()
    func authorize() async throws {
        guard try await store.requestWriteOnlyAccessToEvents() else {
            throw CalendarFlowError.message("カレンダーへの追加が許可されていません。候補は保存されています。")
        }
    }
    /// Caller must persist an uncertain submission BEFORE calling this method.
    func save(_ draft: CalendarProposal, timeZoneID: String) throws -> String {
        guard draft.canRegister, let calendar = store.defaultCalendarForNewEvents else {
            throw CalendarFlowError.message("登録可能なカレンダーと、予定の件名・日時を確認してください。")
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.start; event.endDate = draft.end
        event.timeZone = TimeZone(identifier: timeZoneID)
        event.notes = draft.notes
        // No attendee, invitation, recurrence, alarm or transcript attachment is inferred.
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier ?? "saved"
    }
}

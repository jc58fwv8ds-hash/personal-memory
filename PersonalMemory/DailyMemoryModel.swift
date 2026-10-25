import Foundation

public struct DailyMemory: Codable, Equatable, Sendable {
    public let id: UUID
    public let day: Date
    public let events: [MemoryEvent]
    public let isUserEdited: Bool

    public init(
        id: UUID,
        day: Date,
        events: [MemoryEvent],
        isUserEdited: Bool = false
    ) {
        self.id = id
        self.day = day
        self.events = Self.normalized(events)
        self.isUserEdited = isUserEdited
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let day = try container.decode(Date.self, forKey: .day)
        let events = try container.decodeIfPresent(
            [MemoryEvent].self,
            forKey: .events
        ) ?? []
        let isUserEdited = try container.decodeIfPresent(
            Bool.self,
            forKey: .isUserEdited
        ) ?? false
        self.init(
            id: id,
            day: day,
            events: events,
            isUserEdited: isUserEdited
        )
    }

    private static func normalized(_ events: [MemoryEvent]) -> [MemoryEvent] {
        var seenIDs = Set<UUID>()
        let uniqueEvents = events.enumerated().filter { entry in
            seenIDs.insert(entry.element.id).inserted
        }
        return uniqueEvents.sorted { lhs, rhs in
            if lhs.element.occurredAt == rhs.element.occurredAt {
                return lhs.offset < rhs.offset
            }
            return lhs.element.occurredAt < rhs.element.occurredAt
        }
        .map { $0.element }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case day
        case events
        case isUserEdited
    }
}

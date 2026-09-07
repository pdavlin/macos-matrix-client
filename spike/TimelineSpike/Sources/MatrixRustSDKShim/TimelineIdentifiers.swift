import Foundation

/// Opaque identity of a timeline item, as the diffable data source keys rows.
public struct TimelineUniqueId: Hashable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

/// Identity of an event, or of the local echo that stands in for one.
public struct EventOrTransactionId: Hashable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }

    public static func eventId(eventId: String) -> EventOrTransactionId {
        EventOrTransactionId(id: eventId)
    }
}

/// Whether a back-pagination is in flight. The container renders a decoration
/// row while it is.
public enum PaginationStatus: Equatable, Sendable, CustomDebugStringConvertible {
    case idle(hitTimelineStart: Bool)
    case paginating

    public var debugDescription: String {
        switch self {
        case let .idle(hitTimelineStart):
            return "idle(hitTimelineStart: \(hitTimelineStart))"
        case .paginating:
            return "paginating"
        }
    }
}

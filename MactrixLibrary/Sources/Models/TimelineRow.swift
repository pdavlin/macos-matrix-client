import Foundation

/// Platform-neutral view-model for a single timeline row.
///
/// Row views and layout math consume this type instead of SDK types so the
/// row layer can live in `MactrixLibrary` and port to iOS. SDK
/// `TimelineItem`s are mapped onto this model in the app target, next to the
/// other SDK conformances. Cases mirror the SDK's item shape: message-like
/// events, other events, and non-event rows.
public enum TimelineRow {
    /// A message-like event (SDK `.msgLike` content). The event carries the
    /// message content; rows render it back through the SDK conformance.
    case message(uniqueId: String, event: EventTimelineItem)
    /// Any event that is not message-like, with its display name.
    case state(uniqueId: String, event: EventTimelineItem, name: String)
    /// A non-event row (day divider, read marker, timeline start).
    case virtual(uniqueId: String, item: VirtualTimelineItem)

    /// Opaque stable identifier of the source timeline item. Row identity,
    /// diffing, and view reuse are keyed off this string.
    public var uniqueId: String {
        switch self {
        case let .message(uniqueId, _):
            return uniqueId
        case let .state(uniqueId, _, _):
            return uniqueId
        case let .virtual(uniqueId, _):
            return uniqueId
        }
    }

    /// Stable reuse identifier for the row's view.
    public var reuseId: String {
        switch self {
        case .message:
            return "message"
        case .state:
            return "state"
        case .virtual:
            return "virtual"
        }
    }
}

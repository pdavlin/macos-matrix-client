import Foundation

/// How a message row renders.
///
/// Coarse enough to compute once at map time from content the SDK item
/// already carries, and specific enough that `NSHostingView` recycling hands
/// a row a view whose subview tree it can actually reuse (S-34). A text row
/// and an image row share no layout, so sharing a reuse identifier forced
/// SwiftUI to rebuild the tree on every recycle.
public enum MessageRowKind: String, Hashable, CaseIterable {
    /// Text, notice, and emote bodies: a wrapped text layout.
    case text
    /// Image, video, gallery, and sticker bodies: a sized media layout.
    case media
    /// Audio and file bodies: a fixed-height attachment layout.
    case attachment
    /// Polls, redactions, locations, and anything else message-like.
    case other
}

/// Platform-neutral view-model for a single timeline row.
///
/// Row views and layout math consume this type instead of SDK types so the
/// row layer can live in `MactrixLibrary` and port to iOS. SDK
/// `TimelineItem`s are mapped onto this model in the app target, next to the
/// other SDK conformances.
///
/// Most cases mirror the SDK's item shape. `typingIndicator` and
/// `paginationActivity` are container-owned decoration rows with no SDK item
/// behind them: modelling them as rows keeps one index space for row heights,
/// the height cache, and the scroll anchor, instead of an offset that every
/// index-taking call site would have to remember.
public enum TimelineRow {
    /// A message-like event (SDK `.msgLike` content). The event carries the
    /// message content; rows render it back through the SDK conformance.
    case message(uniqueId: String, event: EventTimelineItem, kind: MessageRowKind, hasReactions: Bool)
    /// Any event that is not message-like, with its display name.
    case state(uniqueId: String, event: EventTimelineItem, name: String)
    /// A non-event row (day divider, read marker, timeline start).
    case virtual(uniqueId: String, item: VirtualTimelineItem)
    /// Who is currently typing, rendered at the newest end (D-3).
    case typingIndicator(uniqueId: String, names: [String])
    /// Back-pagination is in flight, rendered at the oldest end (D-2).
    case paginationActivity(uniqueId: String)
    /// An SDK item that is neither event nor virtual.
    ///
    /// The mapping stays total on purpose. Dropping such an item would
    /// desynchronize the row array from the SDK-ordered item array, and every
    /// index the diff carries would then point at the wrong row.
    case unsupported(uniqueId: String)

    /// Opaque stable identifier of the source timeline item. Row identity,
    /// diffing, and view reuse are keyed off this string.
    public var uniqueId: String {
        switch self {
        case let .message(uniqueId, _, _, _):
            return uniqueId
        case let .state(uniqueId, _, _):
            return uniqueId
        case let .virtual(uniqueId, _):
            return uniqueId
        case let .typingIndicator(uniqueId, _):
            return uniqueId
        case let .paginationActivity(uniqueId):
            return uniqueId
        case let .unsupported(uniqueId):
            return uniqueId
        }
    }

    /// Stable reuse identifier for the row's view.
    ///
    /// Granularity matters: `NSTableView` hands back any view registered
    /// under the same identifier, and `NSHostingView` only reuses its subview
    /// tree when the new root view has the same shape. Splitting by message
    /// kind, and by whether a reaction strip is present, keeps a recycled view
    /// structurally compatible with the row it is about to render.
    public var reuseId: String {
        switch self {
        case let .message(_, _, kind, hasReactions):
            return hasReactions ? "message.\(kind.rawValue).reactions" : "message.\(kind.rawValue)"
        case .state:
            return "state"
        case let .virtual(_, item):
            return "virtual.\(item.reuseIdSuffix)"
        case .typingIndicator:
            return "typingIndicator"
        case .paginationActivity:
            return "paginationActivity"
        case .unsupported:
            return "unsupported"
        }
    }

    /// True for rows the container owns rather than the SDK.
    public var isDecoration: Bool {
        switch self {
        case .typingIndicator, .paginationActivity:
            return true
        case .message, .state, .virtual, .unsupported:
            return false
        }
    }
}

public extension VirtualTimelineItem {
    /// Reuse-identifier suffix. Virtual rows are all dividers, but a date
    /// divider carries a formatted label the other two do not, so they get
    /// separate recycling pools.
    var reuseIdSuffix: String {
        switch self {
        case .dateDivider:
            return "dateDivider"
        case .readMarker:
            return "readMarker"
        case .timelineStart:
            return "timelineStart"
        }
    }
}

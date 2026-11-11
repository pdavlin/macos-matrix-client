import Foundation

// MATRIX-142 (M2.5-3): the input side of the merged timeline. The engine is
// `MergedTimelineMerger` in MergedTimeline.swift.

/// What one item of a member room's timeline is, as the merged timeline sees
/// it (MATRIX-142).
///
/// One enum holds the kind and the time together, so an event without a time
/// or a divider with a time cannot be stated.
public enum MergedTimelineItemKind: Hashable, Sendable {
    /// An event the server accepted, message or state, at its
    /// `origin_server_ts`.
    case event(serverTimestamp: Date)
    /// An event the server has not accepted yet: a local echo that waits,
    /// sends, or failed. `createdAt` is the local creation time. It orders
    /// echoes from different rooms in send order.
    case localEcho(createdAt: Date)
    /// The SDK's date divider. The merge drops it and makes its own.
    case dateDivider
    /// The SDK's read marker. The merge drops it, reads where it sits, and
    /// makes one merged read marker.
    case readMarker
    /// Any other item without an event: the SDK's timeline start, or an item
    /// that is neither event nor virtual. The merge drops it.
    case otherVirtual
}

/// One item of a member room's timeline, as the merge reads it (MATRIX-142).
///
/// The merge reads `mergedItemKind` once per item per run, and
/// `mergedItemId` once per item it shows. Conform with stored properties:
/// a getter that calls across the SDK's FFI would make every recompute pay
/// one FFI call per item.
public protocol MergedTimelineSourceItem {
    /// The item's identifier, unique and stable inside its own room's
    /// timeline: the SDK's `TimelineItem.uniqueId()`. Two rooms may use the
    /// same identifier, because the merge scopes it by room
    /// (`MergedTimelineEntryID.item(roomId:itemId:)`).
    var mergedItemId: String { get }
    /// What the item is, and when it happened.
    var mergedItemKind: MergedTimelineItemKind { get }
}

/// One member room of a merged chat, as the merge reads it (MATRIX-142).
public struct MergedTimelineMember<Item: MergedTimelineSourceItem> {
    /// The member room's ID.
    public var roomId: String
    /// The room's timeline items in SDK order, oldest first. This is the
    /// order of `LiveTimeline.timelineItems`, not the newest-first
    /// `displayItems`.
    public var items: [Item]
    /// True when back-pagination reached the start of the room, so no older
    /// history exists. A member that reached its start does not clamp.
    public var reachedStart: Bool

    public init(roomId: String, items: [Item], reachedStart: Bool) {
        self.roomId = roomId
        self.items = items
        self.reachedStart = reachedStart
    }

    /// The server timestamp of the oldest event this member has loaded: the
    /// first `.event` item in SDK order. Nil when the member has loaded no
    /// server event.
    ///
    /// The first event by position, not the smallest timestamp. A room can
    /// hold an out-of-order timestamp (a bridge backfill), and the smallest
    /// timestamp would then claim history that is not loaded.
    ///
    /// Cost: it reads items from the oldest end up to the first event, which
    /// is a few items in practice (the SDK puts its timeline start and a date
    /// divider before the first event).
    public var oldestLoadedTimestamp: Date? {
        for item in items {
            if case let .event(serverTimestamp) = item.mergedItemKind {
                return serverTimestamp
            }
        }
        return nil
    }
}

extension MergedTimelineMember: Sendable where Item: Sendable {}

/// Where the merged timeline stops at its oldest end (MATRIX-142).
///
/// Each member has loaded history back to its oldest loaded event. Older
/// than that, the member may have events the merge cannot see yet. If the
/// merge showed an older event of another member there, the reader would see
/// a gap: a stretch where one room seems silent only because its history is
/// not loaded. The boundary hides every server event older than the newest
/// of the members' oldest loaded events, so no gap shows. Members that
/// reached their start have no unloaded history and do not clamp.
public enum MergedTimelineBoundary: Hashable, Sendable {
    /// Every member reached its start. Nothing is hidden.
    case open
    /// Server events older than this date are hidden. Events at the date
    /// show.
    case clamped(at: Date)
    /// A member that has not reached its start has loaded no server event
    /// yet, so the merge knows nothing about that member's history. Every
    /// server event is hidden until that member loads one. Local echoes
    /// still show.
    case pending

    /// True when a server event at `serverTimestamp` is hidden. Local echoes
    /// are never hidden: they are at the newest end, not history.
    public func hides(serverTimestamp: Date) -> Bool {
        switch self {
        case .open:
            false
        case let .clamped(at: boundary):
            serverTimestamp < boundary
        case .pending:
            true
        }
    }
}

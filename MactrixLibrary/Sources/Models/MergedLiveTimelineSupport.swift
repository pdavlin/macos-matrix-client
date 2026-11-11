import Foundation

// MATRIX-142 Phase B: the pure parts of Core's `MergedLiveTimeline` that are
// not row building: the send-target activity and the recompute coalescing.

/// One message of a member room, as the send-target rule reads it
/// (MATRIX-142 Phase B, MATRIX-143).
public struct MergedMessageActivity: Hashable, Sendable {
    /// The account's own user sent it.
    public var isOwn: Bool
    /// When it was sent: the server time, or the local time of a local echo.
    public var date: Date

    public init(isOwn: Bool, date: Date) {
        self.isOwn = isOwn
        self.date = date
    }
}

public extension MergedSendTarget.RoomActivity {
    /// The newest message times of one member room, from its items newest
    /// first.
    ///
    /// The newest message is the newest by position in the room's own
    /// timeline (the SDK's order), not the largest time, as the room's own
    /// timeline shows it. Local echoes count: a message the user just sent
    /// is the newest own message.
    ///
    /// Cost: a walk from the newest item that stops when both times are
    /// found.
    ///
    /// - Parameter activities: one value per item, newest first: the
    ///   message's activity, or nil when the item is not a message.
    init(newestFirst activities: some Sequence<MergedMessageActivity?>) {
        var newestMessageAt: Date?
        var newestOwnMessageAt: Date?
        for case let activity? in activities {
            if newestMessageAt == nil {
                newestMessageAt = activity.date
            }
            if activity.isOwn, newestOwnMessageAt == nil {
                newestOwnMessageAt = activity.date
            }
            if newestMessageAt != nil, newestOwnMessageAt != nil {
                break
            }
        }
        self.init(newestMessageAt: newestMessageAt, newestOwnMessageAt: newestOwnMessageAt)
    }
}

/// Collects member-room changes between two recomputes of a merged timeline,
/// so a burst of changes costs one recompute (MATRIX-142 Phase B).
///
/// The merge engine's contract asks for one recompute per batch of diffs.
/// Each member room's timeline reports its own changes; the merged model
/// marks the room dirty here and schedules a flush only for the first mark
/// since the last flush.
///
/// ```swift
/// if coalescer.markDirty(roomId) {
///     Task { @MainActor in flush() }
/// }
/// // later, in flush():
/// let changed = coalescer.beginFlush()
/// ```
public struct MergedRecomputeCoalescer: Sendable {
    /// The rooms that changed since the last flush began.
    public private(set) var dirtyRoomIds: Set<String> = []
    /// A flush is scheduled and has not begun yet.
    public private(set) var isFlushScheduled = false

    public init() {}

    /// Records a change of `roomId`.
    ///
    /// - Returns: true when the caller must schedule a flush: this is the
    ///   first change since the last flush began.
    public mutating func markDirty(_ roomId: String) -> Bool {
        dirtyRoomIds.insert(roomId)
        guard !isFlushScheduled else { return false }
        isFlushScheduled = true
        return true
    }

    /// Begins the scheduled flush. A change marked after this schedules the
    /// next flush.
    ///
    /// - Returns: the rooms that changed since the last flush.
    public mutating func beginFlush() -> Set<String> {
        isFlushScheduled = false
        let dirty = dirtyRoomIds
        dirtyRoomIds = []
        return dirty
    }
}

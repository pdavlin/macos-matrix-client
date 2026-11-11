import Core
import MatrixRustSDK
import Models

/// A merged chat's timeline as the timeline container's row source
/// (MATRIX-142 Wave 2).
///
/// The rows come from `drainRowChanges()` as rows, not SDK items, because
/// date dividers and source notes have no SDK item. Every row of a member
/// room gets that member's `LiveTimeline`, so each action goes to the room
/// that holds the event (`MergedChatRouting.route`).
extension MergedLiveTimeline: TimelineRowSource {
    var displayRows: [TimelineRow] {
        rows
    }

    func drainRowUpdates() -> [TimelineRowDisplayUpdate] {
        drainRowChanges()
    }

    func discardRowUpdates() {
        _ = drainRowChanges()
    }

    /// The member timeline of the row's room. The pagination failure row
    /// gets the first member whose back-pagination failed: it shows that
    /// member's failure (`paginationFailure`), and its retry button retries
    /// that member. Rows of the whole merged chat (date dividers, the
    /// timeline start) get nil.
    ///
    /// Cost per row: at most one prefix check per member room
    /// (`MergedTimelineEntryID.roomId(ofRowId:among:)`).
    func timeline(for row: TimelineRow) -> LiveTimeline? {
        if case .paginationFailure = row {
            return actionTimelines.first { $0.paginationFailure != nil }
        }
        return memberTimeline(forRowId: row.uniqueId)
    }

    /// The member timelines in member order, each once.
    var actionTimelines: [LiveTimeline] {
        var seen = Set<ObjectIdentifier>()
        return merge.rooms
            .compactMap(memberTimeline(for:))
            .filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    var focusTarget: TimelineEventReference? {
        focusedEvent.map { TimelineEventReference(eventId: $0.eventId, roomId: $0.roomId) }
    }

    /// A merged row needs the event's room: the same event ID can be in two
    /// member rooms.
    func rowId(of event: TimelineEventReference) -> String? {
        guard let roomId = event.roomId else { return nil }
        return rowId(ofEvent: event.eventId, inRoom: roomId)
    }

    var reportsNewestVisibleRow: Bool {
        true
    }
}

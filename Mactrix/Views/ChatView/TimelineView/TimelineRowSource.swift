import Foundation
import MatrixRustSDK
import Models

// The timeline spike compiles this file without Core (see spike/GATE.md).
#if canImport(Core)
    import Core
#endif

/// An event the timeline container scrolls to (MATRIX-142 Wave 2).
struct TimelineEventReference: Equatable {
    /// The event, or the transaction of its local echo.
    let eventId: MatrixRustSDK.EventOrTransactionId
    /// The room that holds the event. A single-room source ignores it; a
    /// merged source needs it, because the same event ID could be in two
    /// member rooms.
    let roomId: String?
}

/// What the timeline container reads from the timeline it shows
/// (MATRIX-142 Wave 2).
///
/// Two types conform: `LiveTimeline` (one room, below) and
/// `MergedLiveTimeline` (a merged chat, `MergedLiveTimeline+RowSource.swift`).
/// The container is the same for both, so every invariant it keeps holds for
/// both: pre-measured heights and fingerprints (MATRIX-49, MATRIX-50,
/// MATRIX-63), the reset and insert batch rules (MATRIX-98, MATRIX-130), and
/// the scroll anchor (S-33).
///
/// Observation: the container reads `typingNames`, `isPaginating`,
/// `paginationFailure`, `scrollToBottomRequests`, and `focusTarget` inside
/// `withObservationTracking`, so a conforming type must make them
/// observable (or read observable state to compute them).
@MainActor
protocol TimelineRowSource: AnyObject {
    // MARK: Rows

    /// The rows in display order, newest first, without the container's
    /// decoration rows (typing, pagination). Read on the first load and on
    /// a reset.
    var displayRows: [TimelineRow] { get }

    /// The row changes since the last call, in the order to apply them, and
    /// clears the queue. Indices are display indices into the rows of the
    /// previous drain (`TimelineDisplayChange`).
    func drainRowUpdates() -> [TimelineRowDisplayUpdate]

    /// Clears the change queue without reading it. The container calls it
    /// once, when it starts from `displayRows`.
    func discardRowUpdates()

    // MARK: Rooms

    /// The room timeline that the actions of `row` go to: reply, reaction,
    /// edit, redaction, forward, the reaction picker, the hover bar, and the
    /// read receipts the row shows. Nil for a row that belongs to no room.
    /// The container calls it for every row it shows, so it must be cheap.
    func timeline(for row: TimelineRow) -> LiveTimeline?

    /// Every room timeline of the source, each once: the container observes
    /// their reaction picker requests and connects their Edit-menu slots.
    var actionTimelines: [LiveTimeline] { get }

    // MARK: Decorations

    /// The display names of the people who type now.
    var typingNames: [String] { get }
    /// True while a back-pagination runs.
    var isPaginating: Bool { get }
    /// The failure of the last back-pagination, or nil.
    var paginationFailure: String? { get }

    // MARK: Scroll

    /// A counter; each increment asks the container to scroll to the newest
    /// row.
    var scrollToBottomRequests: Int { get }
    /// Called when the scroll position crosses the bottom threshold.
    func setAtBottom(_ atBottom: Bool)
    /// Loads older rows. Called when the scroll nears the oldest end.
    func paginateBackwards() async

    // MARK: Focus

    /// The event to scroll to, or nil.
    var focusTarget: TimelineEventReference? { get }
    /// The row identifier of `event`, or nil while the source has no row
    /// for it.
    func rowId(of event: TimelineEventReference) -> String?

    // MARK: Read receipts

    /// Whether the container reports the newest visible row through
    /// `noteNewestVisibleRow(id:)`.
    var reportsNewestVisibleRow: Bool { get }
    /// Tells the source which row is the newest visible one, while the
    /// window is key.
    func noteNewestVisibleRow(id rowId: String)
}

extension TimelineRowSource {
    var reportsNewestVisibleRow: Bool {
        false
    }

    func noteNewestVisibleRow(id _: String) {}
}

// MARK: - One room

/// One room's live timeline as the container's row source: the behaviour the
/// container had before MATRIX-142 Wave 2, moved behind the protocol.
///
/// Cost: the same SDK reads as before. Rows are mapped from SDK items once,
/// when a change is drained, as the container did; `discardRowUpdates()`
/// maps nothing.
extension LiveTimeline: TimelineRowSource {
    var displayRows: [TimelineRow] {
        displayItems.map(\.row)
    }

    func drainRowUpdates() -> [TimelineRowDisplayUpdate] {
        drainDisplayChanges().map { update in
            TimelineRowDisplayUpdate(change: update.change, rows: update.items.map(\.row))
        }
    }

    func discardRowUpdates() {
        _ = drainDisplayChanges()
    }

    /// Every row of one room acts on that room.
    func timeline(for _: TimelineRow) -> LiveTimeline? {
        self
    }

    var actionTimelines: [LiveTimeline] {
        [self]
    }

    /// Reads the member list only while someone types, so the container's
    /// typing watch does not wake for a member list change.
    var typingNames: [String] {
        let userIds = room.typingUserIds
        guard !userIds.isEmpty else { return [] }
        let members = room.members
        return userIds.map { userId in
            members.first { $0.userId == userId }?.displayName ?? userId
        }
    }

    var isPaginating: Bool {
        if case .paginating = paginating {
            return true
        }
        return false
    }

    func paginateBackwards() async {
        await fetchOlderMessages()
    }

    var focusTarget: TimelineEventReference? {
        focusedTimelineEventId.map { TimelineEventReference(eventId: $0, roomId: nil) }
    }

    /// One pass over the display order, as the focus jump made before.
    func rowId(of event: TimelineEventReference) -> String? {
        displayItems.first { item in
            item.asEvent()?.eventOrTransactionId == event.eventId
        }?.uniqueId().id
    }
}

import Core
import MatrixRustSDK
import Models

/// Adapts `LiveTimeline` to the container's feed (MATRIX-85).
///
/// Every property reads through to the live timeline and its room, so
/// observation tracking on this adapter tracks the live objects. It adds no
/// SDK calls of its own: the mapping is `TimelineItem.row` from Core.
@MainActor
final class LiveTimelineFeed: TimelineFeed {
    let timeline: LiveTimeline

    init(timeline: LiveTimeline) {
        self.timeline = timeline
    }

    var displayRows: [TimelineRow] {
        timeline.displayItems.map(\.row)
    }

    func drainRowChanges() -> [TimelineRowChange] {
        timeline.drainDisplayChanges().map { update in
            TimelineRowChange(change: update.change, rows: update.items.map(\.row))
        }
    }

    func touchObservedState() {
        _ = timeline.timelineItems
        _ = timeline.room.typingUserIds
        _ = timeline.paginating
        _ = timeline.paginationFailure
        _ = timeline.scrollToBottomRequests
        _ = timeline.focusedTimelineEventId
    }

    /// Resolved against the member list, falling back to the raw user ID,
    /// as the Mac container does.
    var typingNames: [String] {
        let members = timeline.room.members
        return timeline.room.typingUserIds.map { userId in
            members.first { $0.userId == userId }?.displayName ?? userId
        }
    }

    var isPaginating: Bool {
        if case .paginating = timeline.paginating { return true }
        return false
    }

    var paginationFailure: String? { timeline.paginationFailure }
    var isAtBottom: Bool { timeline.isAtBottom }
    var unseenArrivals: Int { timeline.unseenArrivals }
    var scrollToBottomRequests: Int { timeline.scrollToBottomRequests }

    var focusRequestId: String? { timeline.focusedTimelineEventId?.id }

    func itemIndexOfFocusRequest() -> Int? {
        guard let focused = timeline.focusedTimelineEventId else { return nil }
        return timeline.displayItems.firstIndex { item in
            item.asEvent()?.eventOrTransactionId == focused
        }
    }

    func setAtBottom(_ atBottom: Bool) {
        timeline.setAtBottom(atBottom)
    }

    func requestScrollToBottom() {
        timeline.requestScrollToBottom()
    }

    func fetchOlderMessages() async {
        await timeline.fetchOlderMessages()
    }

    func retryPagination() {
        timeline.retryPagination()
    }
}

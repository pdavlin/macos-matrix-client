import Foundation
import MatrixRustSDK
import Models

/// Two timelines are equal when they show the same room and the same thread
/// (or both the room's main timeline).
extension LiveTimeline: Equatable {
    public nonisolated static func == (lhs: LiveTimeline, rhs: LiveTimeline) -> Bool {
        lhs.room.id == rhs.room.id && lhs.focusedThreadId == rhs.focusedThreadId
    }
}

extension LiveTimeline {
    /// Reads the facts the thread panel shows from the thread timeline's
    /// items (MATRIX-183): the reply count and the root's row identifier. A
    /// no-op for a room timeline.
    ///
    /// The reply count is the root's thread summary count from the SDK. If
    /// the root carries no summary, it is the number of message events in the
    /// timeline other than the root: the replies the panel shows. No Matrix
    /// semantics are derived here; both numbers come from items the SDK gave.
    ///
    /// Cost: one pass over the items, as `loadPendingReplyDetails()` makes,
    /// once per diff batch, and only for a thread timeline.
    func refreshThreadFacts() {
        guard let rootId = focusedThreadId else { return }
        var sawEvent = false
        var loadedReplies = 0
        var summaryCount: Int?
        var rootRowId: String?
        for item in timelineItems {
            guard let event = item.asEvent() else { continue }
            sawEvent = true
            guard case let .msgLike(content: content) = event.content else { continue }
            if event.eventOrTransactionId.id == rootId {
                summaryCount = content.threadSummary.map { Int($0.numReplies()) }
                rootRowId = item.uniqueId().id
            } else {
                loadedReplies += 1
            }
        }
        let facts = ThreadTimelineFacts(
            replyCount: sawEvent ? (summaryCount ?? loadedReplies) : nil,
            rootRowId: rootRowId
        )
        if threadFacts != facts {
            threadFacts = facts
        }
    }
}

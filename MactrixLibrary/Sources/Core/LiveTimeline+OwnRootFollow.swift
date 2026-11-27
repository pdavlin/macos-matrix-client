import Foundation
import MatrixRustSDK
import Models

// MARK: - Own-root rule (MATRIX-261)

extension LiveTimeline {
    /// Feeds the own messages of a room timeline to `OwnRootReplyWatch`, and
    /// gives each first thread reply to the own-root rule
    /// (`ThreadFollowStore.firstReplyArrived(toOwnRoot:with:)`). Main
    /// timelines only: a thread timeline holds one thread.
    ///
    /// The room timeline is the place where a thread reply to an own message
    /// shows in every room mode: the root's thread summary changes. The sync
    /// notification path is not: in a Mentions and Keywords room a plain
    /// reply does not notify, and in an All Messages room or a DM the SDK
    /// follows the thread for each notifying reply already (SDK issue #6735).
    /// So the rule covers the rooms that a window shows when the reply
    /// arrives.
    ///
    /// Cost: nothing while the server's MSC4306 support is not known. Else
    /// one pass over the items for each diff batch, as
    /// `loadPendingReplyDetails()` makes.
    func noteOwnRootReplies() {
        guard focusedThreadId == nil, ThreadFollowStore.shared.support == .supported else { return }
        var sightings: [OwnRootSighting] = []
        for item in timelineItems {
            guard let event = item.asEvent(), event.isOwn,
                  case let .eventId(eventId) = event.eventOrTransactionId,
                  case let .msgLike(content: content) = event.content else { continue }
            let replyCount = content.threadSummary.map { Int($0.numReplies()) } ?? 0
            sightings.append(OwnRootSighting(eventId: eventId, replyCount: replyCount))
        }
        let arrived = ownRootReplies.observe(sightings)
        guard !arrived.isEmpty else { return }
        let calls = ThreadSubscriptionCalls(room: room.room)
        for root in arrived {
            Task { await ThreadFollowStore.shared.firstReplyArrived(toOwnRoot: root, with: calls) }
        }
    }
}

import Foundation
import MatrixRustSDK
import Models

// MARK: - Own reaction mark (MATRIX-224)

extension LiveTimeline {
    /// Records in `OwnReactionMarks` whether the user reacted to the newest
    /// message of this room, for the Unanswered filter. Main timelines
    /// only: a thread timeline does not hold the room's newest message.
    ///
    /// Reads timeline items from the newest end up to the first message,
    /// so the cost does not grow with the timeline.
    func noteOwnReactionMark() {
        guard focusedThreadId == nil else { return }
        for item in timelineItems.reversed() {
            guard let event = item.asEvent(), case .msgLike = event.content else { continue }
            let message = ChatListMessageKey(
                senderId: event.sender,
                timestamp: MatrixRustSDK.LatestEventValue.date(event.timestamp)
            )
            let mark = ChatListUnanswered.ownReactionMark(
                message: message,
                isOwn: event.isOwn,
                reactionSenderIds: event.reactions.flatMap { $0.senders.map(\.senderId) },
                ownUserId: room.room.ownUserId()
            )
            OwnReactionMarks.shared.record(mark, roomId: room.id)
            return
        }
    }
}

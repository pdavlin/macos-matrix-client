import Foundation
import MatrixRustSDK
import Models

public extension WindowState {
    /// "Reply in Thread" (MATRIX-216, MATRIX-232): the thread panel opens on
    /// `start.root`, and its composer takes the keyboard focus.
    ///
    /// The thread composer's reply target becomes `message` when
    /// `start.quotedEventId` is set: the reply then quotes that message
    /// inside the thread. Else the target is cleared, and the reply is a
    /// plain message of the thread. The thread-focused timeline sends it, so
    /// the SDK adds the thread relation (`LiveTimeline+ReplyRoute`).
    ///
    /// - Parameters:
    ///   - start: where the reply goes (`ThreadReplyStart.of`).
    ///   - message: the message the user replies to.
    func replyInThread(_ start: ThreadReplyStart, to message: MatrixRustSDK.EventTimelineItem) {
        guard case let .joinedRoom(timeline: roomTimeline) = selectedScreen else { return }
        focusThread(rootEventId: start.root, focusingComposer: true)
        guard case let .focusThread(threadTimeline: thread) = inspectorContent,
              thread.room.id == roomTimeline.room.id,
              thread.focusedThreadId == start.root
        else { return }
        thread.sendReplyTo = start.quotedEventId == nil ? nil : message
    }
}

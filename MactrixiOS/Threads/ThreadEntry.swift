import Core
import MatrixRustSDK
import Models

/// A request to push the thread screen over a room's timeline (MATRIX-245).
///
/// The room's screen keeps it in view state and pushes the screen with
/// `navigationDestination(item:)`. A tap on the thread chip opens the thread
/// with no composer focus. "Reply in Thread" opens it with the focus in its
/// composer, as the Mac `WindowState.replyInThread(_:to:)` does.
struct ThreadScreenRequest: Hashable, Identifiable {
    /// The event ID of the thread root.
    let rootEventId: String
    /// True when the thread composer takes the keyboard focus at open.
    let focusesComposer: Bool
    /// The message the thread composer quotes, or nil for a plain thread
    /// message (`ThreadReplyStart.quotedEventId`). Not part of the identity:
    /// an SDK item has no equality of its own.
    let quotedMessage: MatrixRustSDK.EventTimelineItem?

    var id: String { rootEventId }

    /// A tap on the thread chip of `rootEventId`.
    static func chip(rootEventId: String) -> ThreadScreenRequest {
        ThreadScreenRequest(rootEventId: rootEventId, focusesComposer: false, quotedMessage: nil)
    }

    /// "Reply in Thread" on `message`, with the start that
    /// `ThreadReplyStart.of(eventId:threadRoot:)` gives.
    static func replyInThread(_ start: ThreadReplyStart, to message: MatrixRustSDK.EventTimelineItem) -> ThreadScreenRequest {
        ThreadScreenRequest(
            rootEventId: start.root,
            focusesComposer: true,
            quotedMessage: start.quotedEventId == nil ? nil : message
        )
    }

    static func == (lhs: ThreadScreenRequest, rhs: ThreadScreenRequest) -> Bool {
        lhs.rootEventId == rhs.rootEventId
            && lhs.focusesComposer == rhs.focusesComposer
            && lhs.quotedMessage?.eventOrTransactionId.id == rhs.quotedMessage?.eventOrTransactionId.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rootEventId)
        hasher.combine(focusesComposer)
    }
}

/// What "Reply in Thread" on a message does on iOS (MATRIX-245).
///
/// The Mac opens its thread panel beside the room. On iOS the thread is a
/// screen of its own: the main timeline pushes it, and the thread screen
/// replies in place.
enum ThreadReplyEntry: Equatable {
    /// A message of the room timeline: push the thread screen on
    /// `start.root`, with the focus in its composer.
    case openThread(ThreadReplyStart)
    /// A message of the thread screen: the thread composer replies to it.
    /// `quotesMessage` is false for the root, because each message of a
    /// thread already answers the root (`ReplyRoute`).
    case replyHere(quotesMessage: Bool)

    /// - Parameters:
    ///   - eventId: the event ID of the message.
    ///   - messageThreadRoot: the thread root of the message
    ///     (`MsgLikeContent.threadRoot`), or nil if it is not in a thread.
    ///   - timelineThreadRoot: the thread root of the timeline that shows
    ///     the message, or nil for the room timeline.
    static func of(eventId: String, messageThreadRoot: String?, timelineThreadRoot: String?) -> ThreadReplyEntry {
        let start = ThreadReplyStart.of(eventId: eventId, threadRoot: timelineThreadRoot ?? messageThreadRoot)
        if timelineThreadRoot != nil {
            return .replyHere(quotesMessage: start.quotedEventId != nil)
        }
        return .openThread(start)
    }
}

/// The reply entries of the iOS long-press menu (MATRIX-245, MATRIX-246).
///
/// The shared action model decides them (`MessageActionModel`, its
/// `replyActions(on:for:)` rule): in a room whose network puts every reply
/// in a thread (MATRIX-232, `ThreadedReplyRule`), Reply in Thread takes the
/// place of Reply.
enum TimelineReplyMenu {
    /// - Parameters:
    ///   - subject: the message, with `repliesInThreads` set for its room.
    ///   - inThread: true when the thread screen shows the message.
    /// - Returns: the enabled reply actions, in menu order.
    ///
    /// A phone has no hover row. So in the room timeline the long-press menu
    /// takes the hover row's reply entries (Reply and Reply in Thread), and
    /// a thread is reachable in every room. In the thread screen every reply
    /// goes into the thread, so the menu takes the right-click menu's one
    /// entry.
    static func actions(for subject: MessageActionSubject, inThread: Bool) -> [MessageAction] {
        let surface: MessageActionSurface = inThread ? .contextMenu : .hoverRow
        return MessageActionModel.items(for: subject, on: surface)
            .filter { $0.isEnabled && ($0.action == .reply || $0.action == .replyInThread) }
            .map(\.action)
    }
}

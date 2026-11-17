/// A local echo in a thread that the main composer sent to (MATRIX-173).
///
/// The main timeline hides threaded events, so the main column does not show
/// this echo. `ThreadReplyNotice` decides if the main column must tell the
/// user about it.
public struct ThreadReplyEcho: Equatable, Sendable {
    /// The event ID of the thread root.
    public let threadRoot: String
    /// The transaction ID (or event ID) of the echo in the thread timeline.
    public let itemId: String
    /// The send state the thread timeline reports for the echo.
    public let sendState: LocalSendState?

    public init(threadRoot: String, itemId: String, sendState: LocalSendState?) {
        self.threadRoot = threadRoot
        self.itemId = itemId
        self.sendState = sendState
    }
}

/// The notice above the main composer for a reply to a thread that was not
/// sent (MATRIX-173): "Reply to thread not sent", with Retry, Open Thread,
/// and Discard.
///
/// The rule:
///
/// - A failed send gives a notice.
/// - A pending send gives no notice while the room's send queue runs: a
///   normal send completes in less than a second, and a line that flashes is
///   noise.
/// - A pending send gives a notice while the room's send queue is stopped.
///   The SDK stops the queue after a recoverable failure of an earlier
///   message, and the echo then stays pending with no failure of its own
///   until the queue starts again.
/// - A sent message, or an item that is no local echo, gives no notice.
/// - A thread that the thread panel shows gives no notice: the panel shows
///   the failure on the echo itself.
public struct ThreadReplyNotice: Equatable, Sendable {
    /// What Retry does. The SDK owns the retry semantics (see
    /// `LocalSendState.sendingFailed`).
    public enum Retry: Equatable, Sendable {
        /// Start the room's send queue again. The queue then sends on its own.
        case enableSendQueue
        /// Send this wedged echo again through its send handle.
        case resend
    }

    /// The event ID of the thread root. Open Thread shows this thread.
    public let threadRoot: String
    /// The echo that Retry and Discard act on.
    public let itemId: String
    public let retry: Retry

    public init(threadRoot: String, itemId: String, retry: Retry) {
        self.threadRoot = threadRoot
        self.itemId = itemId
        self.retry = retry
    }

    /// The notice for one echo, or nil if the echo needs none.
    ///
    /// - Parameters:
    ///   - echo: the echo in the thread timeline.
    ///   - isSendQueueEnabled: false if the room's send queue is stopped.
    public static func notice(for echo: ThreadReplyEcho, isSendQueueEnabled: Bool) -> ThreadReplyNotice? {
        switch echo.sendState {
        case nil, .sent:
            return nil
        case .sending:
            guard !isSendQueueEnabled else { return nil }
            return ThreadReplyNotice(threadRoot: echo.threadRoot, itemId: echo.itemId, retry: .enableSendQueue)
        case let .sendingFailed(message: _, isRecoverable: isRecoverable):
            return ThreadReplyNotice(
                threadRoot: echo.threadRoot,
                itemId: echo.itemId,
                retry: isRecoverable ? .enableSendQueue : .resend
            )
        }
    }

    /// The one notice the main column shows: that of the first echo that
    /// needs one. When that message is sent or discarded, the next echo that
    /// needs a notice gets it.
    ///
    /// - Parameters:
    ///   - echoes: the echoes of the threads the main composer sent to.
    ///   - isSendQueueEnabled: false if the room's send queue is stopped.
    ///   - shownThreadRoot: the root of the thread that the thread panel
    ///     shows for this room, or nil if it shows none.
    public static func first(
        in echoes: [ThreadReplyEcho],
        isSendQueueEnabled: Bool,
        shownThreadRoot: String?
    ) -> ThreadReplyNotice? {
        for echo in echoes where echo.threadRoot != shownThreadRoot {
            if let notice = notice(for: echo, isSendQueueEnabled: isSendQueueEnabled) {
                return notice
            }
        }
        return nil
    }
}

/// Where a reply from the composer goes: the room's main timeline or a
/// thread (MATRIX-169).
///
/// The rule decides only the destination. The SDK builds the relation: the
/// pinned SDK takes it from the focus of the timeline that sends (a
/// thread-focused timeline sends `m.thread`, see `LiveTimeline+ReplyRoute`).
///
/// The rule does not start a thread. A reply to a message with no thread
/// stays a plain reply; "Reply in Thread" starts a thread.
public enum ReplyRoute: Equatable, Sendable {
    /// A plain reply (`m.in_reply_to`) in the main timeline.
    case plain(inReplyTo: String)
    /// A message in the thread of `root`. `inReplyTo` is the message it
    /// quotes in that thread, or nil for a message that quotes nothing.
    case thread(root: String, inReplyTo: String?)

    /// The route of a reply.
    ///
    /// - Parameters:
    ///   - composerThreadRoot: the thread root of the composer's timeline
    ///     (the thread panel), or nil for a main timeline.
    ///   - targetEventId: the event ID of the reply target.
    ///   - targetThreadRoot: the thread root of the reply target, or nil if
    ///     the target is not in a thread.
    ///   - targetHasThreadSummary: true if the reply target is a thread root
    ///     (it shows a thread summary).
    public static func route(
        composerThreadRoot: String?,
        targetEventId: String,
        targetThreadRoot: String?,
        targetHasThreadSummary: Bool
    ) -> ReplyRoute {
        // The thread panel: every send goes into its thread.
        if let composerThreadRoot {
            return .thread(root: composerThreadRoot, inReplyTo: quoted(targetEventId, inThreadOf: composerThreadRoot))
        }
        // A message inside a thread: the reply goes into that thread.
        if let targetThreadRoot {
            return .thread(root: targetThreadRoot, inReplyTo: quoted(targetEventId, inThreadOf: targetThreadRoot))
        }
        // A thread root: the reply is the next message of its thread.
        if targetHasThreadSummary {
            return .thread(root: targetEventId, inReplyTo: nil)
        }
        return .plain(inReplyTo: targetEventId)
    }

    /// The thread root, or nil for a plain reply.
    public var threadRoot: String? {
        switch self {
        case .plain: nil
        case let .thread(root, _): root
        }
    }

    /// The event the sent message quotes, or nil.
    public var inReplyTo: String? {
        switch self {
        case let .plain(inReplyTo): inReplyTo
        case let .thread(_, inReplyTo): inReplyTo
        }
    }

    /// A reply to the root is a message of the thread, with no quote: each
    /// message of a thread already answers the root.
    private static func quoted(_ targetEventId: String, inThreadOf root: String) -> String? {
        targetEventId == root ? nil : targetEventId
    }
}

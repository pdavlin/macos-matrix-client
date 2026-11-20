/// Where a reply from the composer goes: the room's main timeline or a
/// thread (MATRIX-169).
///
/// The rule decides only the destination. The SDK builds the relation: the
/// pinned SDK takes it from the focus of the timeline that sends (a
/// thread-focused timeline sends `m.thread`, see `LiveTimeline+ReplyRoute`).
///
/// A reply to a message with no thread stays a plain reply; "Reply in
/// Thread" starts a thread. One exception (MATRIX-216): while the window's
/// thread panel shows the thread of the target, the user started that thread,
/// and a reply to the target goes into it.
public enum ReplyRoute: Equatable, Sendable {
    /// A plain reply (`m.in_reply_to`) in the main timeline.
    case plain(inReplyTo: String)
    /// A message in the thread of `root`. `inReplyTo` is the message it
    /// quotes in that thread, or nil for a message that quotes nothing.
    case thread(root: String, inReplyTo: String?)

    /// The route of a reply.
    ///
    /// The content of the target (text, image, any other message) has no
    /// part in the rule: only its thread facts do.
    ///
    /// - Parameters:
    ///   - composerThreadRoot: the thread root of the composer's timeline
    ///     (the thread panel), or nil for a main timeline.
    ///   - openThreadRoot: the root of the thread that the window's thread
    ///     panel shows in the composer's room, or nil (MATRIX-216).
    ///   - targetEventId: the event ID of the reply target.
    ///   - targetThreadRoot: the thread root of the reply target, or nil if
    ///     the target is not in a thread.
    ///   - targetHasThreadSummary: true if the reply target is a thread root
    ///     that shows a thread chip (`ThreadRootRule`).
    public static func route(
        composerThreadRoot: String?,
        openThreadRoot: String? = nil,
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
        // A thread root, or the root of the thread the panel shows (also
        // before its first reply): the reply is the next message of its
        // thread.
        if targetHasThreadSummary || targetEventId == openThreadRoot {
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

    /// The timeline that sends a message with `route` (MATRIX-216).
    ///
    /// Only a thread-focused SDK timeline sends `m.thread`. A main
    /// timeline's reply has only `m.in_reply_to`, unless the target is in a
    /// thread. So a message for a thread never goes out through a main
    /// timeline.
    ///
    /// - Parameters:
    ///   - route: the reply route, or nil for a message that is not a reply.
    ///   - composerThreadRoot: the thread root of the composer's timeline,
    ///     or nil for a main timeline.
    public static func sendTimeline(for route: ReplyRoute?, composerThreadRoot: String?) -> ReplySendTimeline {
        guard let root = route?.threadRoot, root != composerThreadRoot else { return .composer }
        return .thread(root: root)
    }

    /// A reply to the root is a message of the thread, with no quote: each
    /// message of a thread already answers the root.
    private static func quoted(_ targetEventId: String, inThreadOf root: String) -> String? {
        targetEventId == root ? nil : targetEventId
    }
}

/// The SDK timeline that sends a message (MATRIX-216).
public enum ReplySendTimeline: Equatable, Sendable {
    /// The composer's own timeline: its focus is the destination.
    case composer
    /// A timeline with the focus on the thread of `root`.
    case thread(root: String)
}

import Foundation

/// Which networks put every reply in a thread (MATRIX-232).
///
/// Slack has no inline quote reply. mautrix-slack sends a Matrix reply
/// (`m.in_reply_to`) to Slack as a reply in the thread of the message. If
/// Mactrix shows that reply inline in the main timeline, the two clients show
/// it in different places. So in a room of such a network, every Reply entry
/// point acts as Reply in Thread (`MessageActionModel`), and a reply from a
/// main timeline goes into the thread of its target (`ReplyRoute`).
///
/// The network comes from the room's members (`ChatListNetwork.detect`), as
/// the network badge does. A room the detector does not know keeps the inline
/// reply.
public enum ThreadedReplyRule {
    /// Whether every reply in a room of `network` belongs in a thread.
    ///
    /// - Parameter network: the room's bridged network, or nil for a room
    ///   that is not bridged or whose network is not detected.
    /// - Returns: true for Slack. A plain Matrix room and the other bridges
    ///   keep the inline reply. A new network gets its answer here: the
    ///   switch is exhaustive, so the compiler asks for it.
    public static func repliesInThreads(on network: ChatListNetwork?) -> Bool {
        guard let network else { return false }
        switch network {
        case .slack:
            return true
        case .whatsApp, .signal, .discord, .telegram, .googleChat, .groupMe, .meta, .instagram, .facebook,
             .googleMessages, .linkedIn, .twitter:
            return false
        }
    }
}

/// Where "Reply in Thread" on a message puts the reply (MATRIX-232).
///
/// Matrix threads do not nest. A message in a thread gets its reply in that
/// thread, as a reply to the message inside the thread. Any other message
/// starts its own thread, or continues it if it is a thread root, and the
/// reply is a plain message of that thread.
public struct ThreadReplyStart: Equatable, Sendable {
    /// The event ID of the thread root. The thread panel opens on it.
    public let root: String
    /// The message the thread composer replies to inside the thread, or nil
    /// for a plain thread message.
    public let quotedEventId: String?

    public init(root: String, quotedEventId: String?) {
        self.root = root
        self.quotedEventId = quotedEventId
    }

    /// The start of a reply in the thread of a message.
    ///
    /// - Parameters:
    ///   - eventId: the event ID of the message.
    ///   - threadRoot: the root of the thread that holds the message, or nil
    ///     if the message is not in a thread. A thread root is not in a
    ///     thread of its own.
    public static func of(eventId: String, threadRoot: String?) -> ThreadReplyStart {
        guard let threadRoot, threadRoot != eventId else {
            return ThreadReplyStart(root: eventId, quotedEventId: nil)
        }
        return ThreadReplyStart(root: threadRoot, quotedEventId: eventId)
    }
}

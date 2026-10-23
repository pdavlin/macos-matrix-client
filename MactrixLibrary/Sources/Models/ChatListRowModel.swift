import Foundation

/// Everything a chat-list row or pinned tile draws (MATRIX-67).
///
/// Built in the app target from the SDK room, its `RoomInfo`, and its latest
/// event. The views take this value and nothing else, so a snapshot test can
/// state any row without an SDK room.
public struct ChatListRowModel: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var avatarUrl: String?
    public var isDirect: Bool
    public var preview: String?
    public var timestamp: String?
    public var unread: ChatListUnread
    public var hasSendFailure: Bool
    public var network: ChatListNetwork?

    public init(
        id: String,
        title: String,
        avatarUrl: String? = nil,
        isDirect: Bool = false,
        preview: String? = nil,
        timestamp: String? = nil,
        unread: ChatListUnread = ChatListUnread(),
        hasSendFailure: Bool = false,
        network: ChatListNetwork? = nil
    ) {
        self.id = id
        self.title = title
        self.avatarUrl = avatarUrl
        self.isDirect = isDirect
        self.preview = preview
        self.timestamp = timestamp
        self.unread = unread
        self.hasSendFailure = hasSendFailure
        self.network = network
    }

    /// The VoiceOver label: title, then unread state, then mute.
    public var accessibilityLabel: String {
        var parts = [title]
        if let network {
            parts.append(network.displayName)
        }
        if unread.hasMention {
            parts.append("mentioned")
        }
        if unread.count > 0 {
            parts.append(unread.count == 1 ? "1 unread message" : "\(unread.count) unread messages")
        } else if unread.isUnread {
            parts.append("unread")
        }
        if unread.isMuted {
            parts.append("muted")
        }
        if hasSendFailure {
            parts.append("message failed to send")
        }
        return parts.joined(separator: ", ")
    }
}

/// A room's unread state, derived from the SDK's counters.
public struct ChatListUnread: Equatable, Sendable {
    /// The number in the count capsule. Zero hides the capsule.
    public var count: UInt64
    public var hasMention: Bool
    /// Bold title and unread dot: a count, or the marked-unread flag.
    public var isUnread: Bool
    /// The user's notification mode for the room is mute. The capsule turns
    /// gray; nothing else changes. Display only — the row never sets it.
    public var isMuted: Bool

    public init(count: UInt64 = 0, hasMention: Bool = false, isUnread: Bool = false, isMuted: Bool = false) {
        self.count = count
        self.hasMention = hasMention
        self.isUnread = isUnread
        self.isMuted = isMuted
    }

    /// Builds the state from the SDK's three counters.
    ///
    /// The count is the largest counter. `numUnreadMessages` counts every
    /// "interesting" message whatever the notification settings, so it is the
    /// number a muted or mentions-only room still shows; the other two win
    /// only if the SDK reports them higher.
    public init(
        numUnreadMessages: UInt64,
        numUnreadNotifications: UInt64,
        numUnreadMentions: UInt64,
        isMarkedUnread: Bool,
        isMuted: Bool
    ) {
        let count = max(numUnreadMessages, numUnreadNotifications, numUnreadMentions)
        self.init(
            count: count,
            hasMention: numUnreadMentions > 0,
            isUnread: count > 0 || isMarkedUnread,
            isMuted: isMuted
        )
    }
}

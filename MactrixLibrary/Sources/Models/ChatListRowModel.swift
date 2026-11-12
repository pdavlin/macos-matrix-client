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
    /// MATRIX-129: the room's visible heroes (`ChatListHero.visible`), in
    /// server order. They feed the bubble cluster and a direct chat's avatar.
    public var heroes: [ChatListHero]
    /// MATRIX-129: joined members other than the user, for the cluster's
    /// "+N" label. Zero when unknown.
    public var otherMemberCount: Int
    /// MATRIX-141: a merged chat's other member networks, drawn as further
    /// badges after `network` (see `badgeNetworks`). Empty for a plain room.
    public var additionalNetworks: [ChatListNetwork] = []
    /// MATRIX-148: the account the chat belongs to on its network (a Slack
    /// workspace). Its icon replaces the network letter on the avatar badge.
    /// Nil for a chat in no named space, and for a merged chat.
    public var account: ChatAccount?

    public init(
        id: String,
        title: String,
        avatarUrl: String? = nil,
        isDirect: Bool = false,
        preview: String? = nil,
        timestamp: String? = nil,
        unread: ChatListUnread = ChatListUnread(),
        hasSendFailure: Bool = false,
        network: ChatListNetwork? = nil,
        heroes: [ChatListHero] = [],
        otherMemberCount: Int = 0
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
        self.heroes = heroes
        self.otherMemberCount = otherMemberCount
    }

    /// What the avatar draws (MATRIX-129). See `ChatListAvatarChoice.choose`.
    public var avatarChoice: ChatListAvatarChoice {
        ChatListAvatarChoice.choose(roomId: id, title: title, avatarUrl: avatarUrl, isDirect: isDirect, heroes: heroes)
    }

    /// Joined members other than the user: the SDK's joined count minus one,
    /// never below zero (MATRIX-129).
    ///
    /// - Parameter joinedMembersCount: the SDK's `RoomInfo.joinedMembersCount`,
    ///   which counts the user.
    public static func countOtherMembers(joinedMembersCount: UInt64) -> Int {
        joinedMembersCount > 0 ? Int(clamping: joinedMembersCount - 1) : 0
    }

    /// The VoiceOver label: title, then unread state, then mute.
    public var accessibilityLabel: String {
        var parts = [title]
        parts.append(contentsOf: badgeNetworks.map(\.displayName))
        if let account {
            parts.append(account.name)
        }
        if unread.hasMention {
            parts.append("mentioned")
        }
        if unread.count > 0 {
            parts.append(unread.count == 1 ? "1 unread message" : "\(unread.count) unread messages")
        } else if unread.isUnread {
            parts.append("unread")
        }
        if unread.isMutedByLabel {
            parts.append("muted by label")
        } else if unread.isMuted {
            parts.append("muted")
        }
        if hasSendFailure {
            parts.append("message failed to send")
        }
        return parts.joined(separator: ", ")
    }

    /// The label under a pinned favourite tile (MATRIX-123).
    ///
    /// A direct chat shows the other person's first name, as Beeper does; a
    /// group keeps its full name. The tooltip and the VoiceOver label keep
    /// the full title.
    public var pinnedTitle: String {
        isDirect ? Self.firstName(of: title) : title
    }

    /// The first word of a display name.
    ///
    /// - Parameter displayName: a person's display name, for example
    ///   "Seth Redacted (WhatsApp)".
    /// - Returns: the text before the first whitespace ("Seth"), or the whole
    ///   trimmed name when it has one word. A blank name comes back unchanged.
    ///
    /// ```swift
    /// ChatListRowModel.firstName(of: "  Seth Redacted ") // "Seth"
    /// ```
    public static func firstName(of displayName: String) -> String {
        let firstWord = displayName.split(whereSeparator: \.isWhitespace).first
        return firstWord.map(String.init) ?? displayName
    }

    /// The row tooltip: the title, and why the row is muted when a label
    /// muted it (MATRIX-77).
    public var helpText: String {
        unread.isMutedByLabel ? "\(title)\nMuted by Label" : title
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
    /// MATRIX-77: the room is muted because every label that holds it is
    /// muted, not by its own notification mode. Implies `isMuted`.
    public var isMutedByLabel: Bool

    public init(
        count: UInt64 = 0,
        hasMention: Bool = false,
        isUnread: Bool = false,
        isMuted: Bool = false,
        isMutedByLabel: Bool = false
    ) {
        self.count = count
        self.hasMention = hasMention
        self.isUnread = isUnread
        self.isMuted = isMuted || isMutedByLabel
        self.isMutedByLabel = isMutedByLabel
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
        isMuted: Bool,
        isMutedByLabel: Bool = false
    ) {
        let count = max(numUnreadMessages, numUnreadNotifications, numUnreadMentions)
        self.init(
            count: count,
            hasMention: numUnreadMentions > 0,
            isUnread: count > 0 || isMarkedUnread,
            isMuted: isMuted,
            // The room's own mute is the stronger statement: name the label
            // only when it is the reason.
            isMutedByLabel: isMutedByLabel && !isMuted
        )
    }
}

import Foundation

/// The unread inputs of one room, as the Dock badge reads them (MATRIX-119).
///
/// Built in Core from the SDK's `RoomInfo`. A plain value, so the counting
/// rule in `DockBadge` is unit tested without an SDK room.
public struct UnreadChatState: Equatable, Sendable {
    public var roomId: String
    /// `RoomInfo.numUnreadNotifications`: unread events that the push rules
    /// say notify.
    public var numUnreadNotifications: UInt64
    /// `RoomInfo.numUnreadMessages`: every "interesting" unread message,
    /// whatever the push rules say.
    public var numUnreadMessages: UInt64
    /// `RoomInfo.isDirect`.
    public var isDirect: Bool
    /// `RoomInfo.isMarkedUnread`: the user marked the room unread.
    public var isMarkedUnread: Bool
    /// The room's own notification mode is mute, the same flag that grays a
    /// chat-list row's capsule.
    public var isMuted: Bool

    public init(
        roomId: String,
        numUnreadNotifications: UInt64 = 0,
        numUnreadMessages: UInt64 = 0,
        isDirect: Bool = false,
        isMarkedUnread: Bool = false,
        isMuted: Bool = false
    ) {
        self.roomId = roomId
        self.numUnreadNotifications = numUnreadNotifications
        self.numUnreadMessages = numUnreadMessages
        self.isDirect = isDirect
        self.isMarkedUnread = isMarkedUnread
        self.isMuted = isMuted
    }
}

/// The Dock badge: the number of chats with unread activity, Beeper style
/// (MATRIX-119).
///
/// The badge counts chats, not messages. Ten unread messages in one chat add
/// one. This file holds the whole rule, so a change to it is a change here and
/// in `DockBadgeTests`.
public enum DockBadge {
    /// Whether one chat adds one to the badge.
    ///
    /// The rule, in order:
    /// 1. A room whose own notification mode is mute never counts.
    /// 2. A room muted by its labels (MATRIX-77: every label that holds it is
    ///    muted) never counts.
    /// 3. Otherwise the room counts if ANY of these is true:
    ///    - it has unread notifications (`numUnreadNotifications > 0`),
    ///    - it is a DM and has unread messages (`numUnreadMessages > 0`),
    ///    - the user marked it unread.
    ///
    /// Spaces never reach this function: the room list that feeds it uses the
    /// SDK's non-space filter.
    ///
    /// - Parameters:
    ///   - chat: the room's unread inputs.
    ///   - isMutedByLabel: the room is in `ChatLabelDocument.labelMutedRoomIds`.
    /// - Returns: true if the chat adds one to the badge.
    public static func counts(_ chat: UnreadChatState, isMutedByLabel: Bool) -> Bool {
        if chat.isMuted || isMutedByLabel {
            return false
        }
        if chat.numUnreadNotifications > 0 {
            return true
        }
        if chat.isDirect, chat.numUnreadMessages > 0 {
            return true
        }
        return chat.isMarkedUnread
    }

    /// The number of chats that `counts(_:isMutedByLabel:)` accepts.
    ///
    /// - Parameters:
    ///   - chats: the unread inputs of every non-space room.
    ///   - labelMutedRoomIds: `ChatLabelDocument.labelMutedRoomIds`.
    /// - Returns: the count, zero or more.
    public static func unreadChatCount(
        _ chats: some Sequence<UnreadChatState>,
        labelMutedRoomIds: Set<String>
    ) -> Int {
        chats.reduce(into: 0) { count, chat in
            if counts(chat, isMutedByLabel: labelMutedRoomIds.contains(chat.roomId)) {
                count += 1
            }
        }
    }

    /// The text for `NSDockTile.badgeLabel`.
    ///
    /// - Parameters:
    ///   - unreadChatCount: the result of `unreadChatCount(_:labelMutedRoomIds:)`.
    ///   - isEnabled: `NotificationPreferences.showsDockBadge`.
    /// - Returns: the count as digits, or nil (no badge) when the count is zero
    ///   or the user turned the badge off.
    public static func label(unreadChatCount: Int, isEnabled: Bool) -> String? {
        guard isEnabled, unreadChatCount > 0 else { return nil }
        return String(unreadChatCount)
    }
}

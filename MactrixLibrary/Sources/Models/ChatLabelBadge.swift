import Foundation

/// The unread mark on a label-rail item (MATRIX-77). Beeper's AccountBadge:
/// a count capsule or a plain dot.
public enum ChatLabelBadge: Equatable, Sendable {
    case none
    /// Unread activity that does not count: muted chats, or chats marked
    /// unread with no unread messages.
    case dot
    /// The number of chats in the label with unread messages that are not
    /// muted.
    case count(Int)

    /// The badge for `label`, given the unread state of the rooms the app
    /// knows. Rooms with no entry in `unread` count as read.
    ///
    /// A room is muted here when its own notification mode is mute OR the
    /// label itself is muted, so a muted label shows at most a dot.
    ///
    /// A room in `lowPriorityRoomIds` adds nothing (MATRIX-180).
    public static func badge(
        for label: ChatLabel,
        lowPriorityRoomIds: Set<String> = [],
        unread: [String: ChatListUnread]
    ) -> ChatLabelBadge {
        badge(forRooms: label.rooms, isMuted: label.isMuted, lowPriorityRoomIds: lowPriorityRoomIds, unread: unread)
    }

    /// The badge for a set of rooms: a label's rooms, or the chats of a space
    /// (MATRIX-167). Rooms with no entry in `unread` count as read.
    ///
    /// This is the one rule for every rail badge. A muted room gives a dot at
    /// most. A room with the Matrix low priority tag gives nothing, no count
    /// and no dot (MATRIX-180): the Inbox hides it, so the rail does not
    /// point at it.
    ///
    /// - Parameters:
    ///   - rooms: the room IDs.
    ///   - isMuted: the whole set is muted, so it shows at most a dot.
    ///   - lowPriorityRoomIds: the rooms with the low priority tag.
    ///   - unread: the unread state by room ID.
    public static func badge(
        forRooms rooms: some Sequence<String>,
        isMuted: Bool = false,
        lowPriorityRoomIds: Set<String> = [],
        unread: [String: ChatListUnread]
    ) -> ChatLabelBadge {
        var counted = 0
        var hasActivity = false
        for roomId in rooms where !lowPriorityRoomIds.contains(roomId) {
            guard let state = unread[roomId], state.isUnread else { continue }
            hasActivity = true
            if state.count > 0, !state.isMuted, !isMuted {
                counted += 1
            }
        }
        if counted > 0 {
            return .count(counted)
        }
        return hasActivity ? .dot : .none
    }

    /// Words for VoiceOver and the item tooltip, or nil for no badge.
    public var accessibilityDescription: String? {
        switch self {
        case .none: nil
        case .dot: "unread activity"
        case let .count(count): count == 1 ? "1 unread chat" : "\(count) unread chats"
        }
    }
}

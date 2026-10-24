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
    public static func badge(for label: ChatLabel, unread: [String: ChatListUnread]) -> ChatLabelBadge {
        var counted = 0
        var hasActivity = false
        for roomId in label.rooms {
            guard let state = unread[roomId], state.isUnread else { continue }
            hasActivity = true
            if state.count > 0, !state.isMuted, !label.isMuted {
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

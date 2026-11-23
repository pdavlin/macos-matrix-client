import Foundation

/// Settings > Inbox > "After Archive, Snooze or Mark Read, open the next
/// chat" (MATRIX-222). On by default, as in Beeper (`AFTER_ARCHIVE` and
/// `AFTER_TOGGLE_READ` default to `SELECT_NEXT_THREAD`).
public enum InboxFlowPreferences {
    /// `UserDefaults` key of the switch.
    public static let storageKey = "opensNextChatAfterInboxAction"
    /// The value when the user never changed it.
    public static let defaultValue = true

    /// The stored value, or the default.
    public static func isOn(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? defaultValue
    }
}

/// The inbox flow (MATRIX-222): what opens after an action on the open
/// chat, and which chats "Archive All Read" archives.
public enum ChatListInboxFlow {
    /// What the window opens after Archive, Snooze, or Mark as Read on its
    /// open chat.
    public enum NextChat: Equatable, Sendable {
        /// The open chat is not in the visible list: nothing moves.
        case keep
        /// Open this chat.
        case open(ChatSelection)
        /// The list has no other chat: the window selects nothing.
        case clear
    }

    /// The chat to open after the action on `open`: the row below it in
    /// the visible list; at the end of the list, the row above; with no
    /// other row, nothing.
    ///
    /// Read from the list as it is before the action, so the open chat's
    /// row is still in it. A merged chat is one row (MATRIX-141), and the
    /// next row can be a merged chat.
    ///
    /// ```swift
    /// // The list is A, B, C, and B is open.
    /// ChatListInboxFlow.nextChat(after: .room("B"), in: items) // .open(.room("C"))
    /// // C is open.
    /// ChatListInboxFlow.nextChat(after: .room("C"), in: items) // .open(.room("B"))
    /// ```
    ///
    /// - Parameters:
    ///   - open: the window's open chat.
    ///   - items: the visible list in the order the sidebar shows it
    ///     (`VisibleChatList.ordered`: the pinned grid, then the list).
    public static func nextChat(after open: ChatSelection, in items: [ChatListItem]) -> NextChat {
        guard let index = items.firstIndex(where: { $0.id == open.itemId }) else {
            return .keep
        }
        let below = items.index(after: index)
        if below < items.endIndex {
            return .open(items[below].selection)
        }
        if index > items.startIndex {
            return .open(items[items.index(before: index)].selection)
        }
        return .clear
    }

    /// The chats "Archive All Read" archives: the read rows of the chat
    /// list, in list order. The pinned grid is left out, so the favourites
    /// stay where the user put them.
    public static func archiveAllReadTargets(in visible: VisibleChatList<ChatListItem>) -> [ChatListItem] {
        visible.list.filter { !$0.row.unread.isUnread }
    }

    /// The confirmation's title for `count` read chats.
    public static func archiveAllReadTitle(count: Int) -> String {
        switch count {
        case 0: "No Read Chats to Archive"
        case 1: "Archive 1 Read Chat?"
        default: "Archive \(count) Read Chats?"
        }
    }

    /// The confirmation's text for `count` read chats.
    public static func archiveAllReadMessage(count: Int) -> String {
        guard count > 0 else {
            return "Every chat in this list is unread or pinned."
        }
        return "Pinned chats stay. A new message from someone else brings an archived chat back to the Inbox."
    }
}

/// The confirmation of "Archive All Read" (MATRIX-222): the chats it
/// counted when the user chose the command.
public struct ArchiveAllReadRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The chat-list row IDs (`ChatListItem.id`) of the read chats.
    public var itemIds: [String]

    public init(id: UUID = UUID(), itemIds: [String]) {
        self.id = id
        self.itemIds = itemIds
    }

    /// The number the confirmation gives.
    public var count: Int {
        itemIds.count
    }
}

public extension InboxNotice {
    /// The note after "Archive All Read" archived `count` chats
    /// (MATRIX-222).
    static func archivedAll(count: Int, undoStates: [String: InboxRoomState]) -> InboxNotice {
        InboxNotice(message: count == 1 ? "Archived 1 chat" : "Archived \(count) chats", undoStates: undoStates)
    }
}

import Foundation

/// What a main window selects: one room or one merged chat (MATRIX-141,
/// Phase B).
///
/// A window holds one of the two, never both. A merged chat is selected by
/// its ID (a UUID string), a room by its room ID, so `itemId` is also the ID
/// of the chat-list row (`ChatListItem.id`).
public enum ChatSelection: Hashable, Sendable {
    case room(String)
    case merged(String)

    /// The room ID, or the merged chat's ID: the ID of the chat-list row
    /// that shows this selection.
    public var itemId: String {
        switch self {
        case let .room(roomId): roomId
        case let .merged(mergedChatId): mergedChatId
        }
    }

    /// The room ID when a room is selected.
    public var roomId: String? {
        if case let .room(roomId) = self {
            return roomId
        }
        return nil
    }

    /// The merged chat's ID when a merged chat is selected.
    public var mergedChatId: String? {
        if case let .merged(mergedChatId) = self {
            return mergedChatId
        }
        return nil
    }
}

/// The selection rules for merged chats (MATRIX-141, contract §4 M2.5).
///
/// A member room never shows on its own in a main window: every path that
/// asks for a room (a click, a notification, a `matrix:` URL, ⌘K, the Go
/// menu, window restoration) goes through `selection(showing:document:)`,
/// and the window re-checks its selection with `resolve(_:document:previous:)`
/// whenever the merged chats change. A single-room window (MATRIX-116) keeps
/// its room and does not use these rules.
public enum MergedChatSelection {
    /// The selection that shows `roomId`: the merged chat that holds the
    /// room, or the room itself when it is in no merged chat.
    ///
    /// ```swift
    /// // Seth's merged chat "m1" holds !slack1 and !slack2.
    /// MergedChatSelection.selection(showing: "!slack1", document: document) // .merged("m1")
    /// MergedChatSelection.selection(showing: "!other", document: document)  // .room("!other")
    /// ```
    public static func selection(showing roomId: String, document: MergedChatDocument) -> ChatSelection {
        if let merge = document.merge(containing: roomId) {
            return .merged(merge.id)
        }
        return .room(roomId)
    }

    /// The selection a chat-list row stands for.
    ///
    /// - Parameters:
    ///   - itemId: `ChatListItem.id`: a room ID or a merged chat's ID.
    ///   - document: the account's merged chats.
    /// - Returns: `.merged` when the document holds a merged chat with this
    ///   ID, else the selection that shows the room.
    public static func selection(forItemId itemId: String, document: MergedChatDocument) -> ChatSelection {
        if document.merge(id: itemId) != nil {
            return .merged(itemId)
        }
        return selection(showing: itemId, document: document)
    }

    /// The selection a window should hold after the merged chats changed, or
    /// after the window selected a room.
    ///
    /// - A room that is a member shows its merged chat.
    /// - A merged chat that `document` still holds stays selected.
    /// - A merged chat that `previous` held and `document` no longer holds
    ///   (it was unmerged, here or on another device) shows its default room,
    ///   or that room's new merged chat.
    /// - A merged chat that neither document holds stays selected. This is
    ///   the window restored before the first read of the merged chats; the
    ///   detail area shows nothing for it until the read lands.
    ///
    /// - Parameters:
    ///   - current: the window's selection, or nil.
    ///   - document: the merged chats now.
    ///   - previous: the merged chats before the change. Pass the empty
    ///     document when nothing changed.
    /// - Returns: the selection to hold. Equal to `current` when nothing
    ///   needs to move.
    public static func resolve(
        _ current: ChatSelection?,
        document: MergedChatDocument,
        previous: MergedChatDocument = MergedChatDocument()
    ) -> ChatSelection? {
        switch current {
        case nil:
            return nil
        case let .room(roomId):
            return selection(showing: roomId, document: document)
        case let .merged(mergedChatId):
            if document.merge(id: mergedChatId) != nil {
                return current
            }
            guard let removed = previous.merge(id: mergedChatId), let fallback = removed.effectiveDefaultRoom else {
                return current
            }
            return selection(showing: fallback, document: document)
        }
    }

    /// What a window does with a notification click (MATRIX-116 rules, with
    /// MATRIX-141's merged chats).
    public enum NotificationFocus: Equatable, Sendable {
        /// The key window is the room window of the notification's room. It
        /// already shows the room: clear the request and do nothing else.
        case alreadyShown
        /// The key window is the room window of another room. Bring a main
        /// window forward and keep the request for it.
        case bringMainWindowForward
        /// Select this in the key window (a main window) and clear the
        /// request.
        case select(ChatSelection)
    }

    /// Decides what the key window does with a click on a notification from
    /// `roomId`.
    ///
    /// - Parameters:
    ///   - roomId: the room the notification came from.
    ///   - singleRoomId: the key window's room when it is a room window, or
    ///     nil for a main window.
    ///   - document: the account's merged chats.
    /// - Returns: the action. A main window selects the room's merged chat
    ///   when the room is a member.
    public static func notificationFocus(
        roomId: String,
        singleRoomId: String?,
        document: MergedChatDocument
    ) -> NotificationFocus {
        if let singleRoomId {
            return singleRoomId == roomId ? .alreadyShown : .bringMainWindowForward
        }
        return .select(selection(showing: roomId, document: document))
    }
}

public extension ChatListItem {
    /// The selection a click on this row makes.
    var selection: ChatSelection {
        switch self {
        case let .room(entry): .room(entry.id)
        case let .merged(merged): .merged(merged.id)
        }
    }
}

import Foundation

public extension ChatListNavigation {
    /// The chat Go > Next Unread Chat (⌘U) opens (MATRIX-223): the first
    /// unread row below the open chat. Past the end of the list it goes on
    /// from the top, so it wraps.
    ///
    /// The open chat is never the answer, unread or not: the window already
    /// shows it. With no chat open, or an open chat the list does not show,
    /// the search starts at the top. `nil` when no other row is unread.
    ///
    /// A row is unread when it draws the unread dot and the bold title
    /// (`ChatListUnread.isUnread`): a count, or the marked-unread flag. A
    /// muted chat with a count counts. A merged chat is one row, unread
    /// when any present member is.
    ///
    /// ```swift
    /// // A, B (unread), C, D (unread). C is open.
    /// ChatListNavigation.nextUnread(after: "C", in: items) // D
    /// // D is open: past the end, from the top.
    /// ChatListNavigation.nextUnread(after: "D", in: items) // B
    /// ```
    ///
    /// - Parameters:
    ///   - selectedItemId: the open chat's row ID (`ChatSelection.itemId`).
    ///   - items: the visible list in the order the sidebar shows it
    ///     (`VisibleChatList.ordered`: the pinned grid, then the list).
    static func nextUnread(after selectedItemId: String?, in items: [ChatListItem]) -> ChatSelection? {
        let start = selectedItemId.flatMap { id in items.firstIndex { $0.id == id } }
        let searchOrder: [ChatListItem] = if let start {
            Array(items[items.index(after: start)...] + items[..<start])
        } else {
            items
        }
        return searchOrder.first { $0.row.unread.isUnread }?.selection
    }
}

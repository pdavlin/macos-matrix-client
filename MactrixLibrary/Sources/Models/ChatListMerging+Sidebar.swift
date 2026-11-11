import Foundation

// MATRIX-141 Phase B: the sidebar's chat list with merged chats.

public extension ChatListMerging {
    /// The rooms a window's sidebar shows, with merged chats folded in, split
    /// into the pinned grid and the list.
    ///
    /// The order of the steps matters (MATRIX-141 Phase A note):
    /// 1. Filter. The SDK already applied the chat-list filter and the
    ///    selected label's room set before `entries` arrive. With no label
    ///    selected (the Inbox), this drops the rooms of labels hidden from the
    ///    Inbox (MATRIX-77), as `VisibleChatList.visible` does.
    /// 2. Merge. The member rows that are left become one merged row
    ///    (`items(entries:document:)`).
    /// 3. Split. Favourites go to the grid, the rest to the list. A merged
    ///    chat is a favourite when any present member is.
    ///
    /// Labels and merged chats: a merged row shows under a label when any of
    /// its members is in the label, because the SDK's label filter keeps that
    /// member. It then sums only the members in the label. In the Inbox, a
    /// merged row shows when any member is outside every hidden label.
    ///
    /// - Parameters:
    ///   - entries: the client's chat rooms in SDK (recency) order, without
    ///     spaces, favourites included.
    ///   - labels: the labels document.
    ///   - selectedLabelId: the window's selected label. An ID the labels do
    ///     not hold counts as no label.
    ///   - document: the account's merged chats.
    /// - Returns: the pinned grid and the list. `ordered` is what the Go menu
    ///   walks.
    static func visible(
        entries: [ChatListEntry],
        labels: ChatLabelDocument,
        selectedLabelId: String?,
        document: MergedChatDocument
    ) -> VisibleChatList<ChatListItem> {
        let selectedLabel = selectedLabelId.flatMap(labels.label(id:))
        let hidden = selectedLabel == nil ? labels.inboxHiddenRoomIds : []
        let shown = hidden.isEmpty ? entries : entries.filter { !hidden.contains($0.id) }
        return visible(entries: shown, document: document)
    }

    /// The merged chat-list entry for one merged chat from its members'
    /// entries, as the chat list builds it. The detail placeholder uses it
    /// for the merged avatar, title, and network badges.
    ///
    /// - Parameters:
    ///   - merge: the merged chat.
    ///   - members: the entries of the members that are known, in any
    ///     order. Entries of other rooms are ignored.
    /// - Returns: nil when no member is known.
    static func entry(for merge: MergedChat, members: [ChatListEntry]) -> MergedChatListEntry? {
        let rooms = Set(merge.rooms)
        var seen = Set<String>()
        let owned = members.filter { rooms.contains($0.id) && seen.insert($0.id).inserted }
        return mergedEntry(merge: merge, members: owned)
    }
}

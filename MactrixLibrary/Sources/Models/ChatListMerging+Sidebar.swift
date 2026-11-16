import Foundation

// MATRIX-141 Phase B: the sidebar's chat list with merged chats.

public extension ChatListMerging {
    /// The rooms a window's sidebar shows for the Inbox or a label.
    ///
    /// The same as `visible(entries:filter:labels:spaces:document:)` with a
    /// label filter, or the Inbox for a nil ID (MATRIX-167: the rail has one
    /// filter path).
    ///
    /// - Parameters:
    ///   - entries: the client's chat rooms in SDK (recency) order, without
    ///     spaces, favourites included.
    ///   - labels: the labels document.
    ///   - selectedLabelId: the window's selected label. An ID the labels do
    ///     not hold counts as no label.
    ///   - document: the account's merged chats.
    static func visible(
        entries: [ChatListEntry],
        labels: ChatLabelDocument,
        selectedLabelId: String?,
        document: MergedChatDocument
    ) -> VisibleChatList<ChatListItem> {
        visible(
            entries: entries,
            filter: selectedLabelId.map(ChatListRailFilter.label) ?? .inbox,
            labels: labels,
            spaces: RoomSpaceMap(),
            document: document
        )
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

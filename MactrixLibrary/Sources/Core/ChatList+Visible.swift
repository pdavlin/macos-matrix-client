import Foundation
import Models

// MATRIX-248: the client glue of the chat list that the Mac sidebar and the
// iOS chat list share. The rules are in Models: the inbox placement and the
// merged chats in `ChatListMerging.visible(entries:filter:labels:spaces:document:inbox:placement:)`,
// the SDK narrowing in `ChatListFilter.narrowingRoomIds(rail:placementRoomIds:draftRoomIds:)`.
// These functions feed them from the client, so both apps call one rule.

public extension MatrixClient {
    /// The client's chat rooms: `rooms` without the spaces, in SDK order.
    var chatRooms: [SidebarRoom] {
        rooms.filter { !$0.room.isSpace() }
    }

    /// The chat-list entries of `rooms`, in SDK order: each row with its
    /// label mute (MATRIX-77), its account for the badge (MATRIX-148), and
    /// its unanswered state (MATRIX-224). The broadcast reads them too
    /// (MATRIX-172).
    ///
    /// - Parameters:
    ///   - rooms: chat rooms, without spaces (`chatRooms`).
    ///   - now: decides the rows' timestamp buckets.
    func chatListEntries(rooms: [SidebarRoom], now: Date = .now) -> [ChatListEntry] {
        let mutedByLabel = labels?.document.labelMutedRoomIds ?? []
        let accounts = roomAccounts
        // MATRIX-224: the own reactions the open timelines saw.
        let reactionMarks = OwnReactionMarks.shared.marks
        return rooms.map { room in
            var entry = room.chatListEntry(now: now, mutedByLabel: mutedByLabel.contains(room.id))
            entry.row.account = accounts.account(of: room.id, network: entry.row.network)
            entry.isUnanswered = ChatListUnanswered.isUnanswered(room.latestEvent, ownReaction: reactionMarks[room.id])
            return entry
        }
    }

    /// The chat list for a rail filter and a list filter: the pinned grid
    /// and the list, with the inbox state and the merged chats applied.
    ///
    /// MATRIX-206, MATRIX-207: archived and snoozed chats show under their
    /// own list filter only. MATRIX-141: a merged chat is one item.
    ///
    /// - Parameters:
    ///   - entries: the chat-list entries (`chatListEntries(rooms:now:)`).
    ///   - rail: the rail filter. iOS has no rail: `.inbox`.
    ///   - filter: the list filter. It picks the inbox placement.
    ///   - labels: the labels document. The Inbox leaves out the rooms of
    ///     labels hidden from the Inbox.
    func visibleChatList(
        entries: [ChatListEntry],
        rail: ChatListRailFilter,
        filter: ChatListFilter,
        labels: ChatLabelDocument
    ) -> VisibleChatList<ChatListItem> {
        ChatListMerging.visible(
            entries: entries,
            filter: rail,
            labels: labels,
            spaces: roomAccounts.spaceMap,
            document: mergedChats?.document ?? MergedChatDocument(),
            inbox: inbox?.document ?? InboxStateDocument(),
            placement: filter.inboxPlacement
        )
    }
}

@MainActor
public extension ChatListFilter {
    /// The rooms the SDK list is narrowed to for this filter on `client`:
    /// `narrowingRoomIds(rail:placementRoomIds:draftRoomIds:)` with the
    /// client's inbox states and drafts. Nil when nothing narrows the list.
    ///
    /// - Parameters:
    ///   - rail: the rail filter's rooms, or nil for the Inbox (and on iOS,
    ///     which has no rail).
    ///   - client: the signed-in client, or nil.
    func narrowingRoomIds(rail: [String]?, client: MatrixClient?) -> [String]? {
        narrowingRoomIds(
            rail: rail,
            placementRoomIds: { client?.inbox?.roomIds(in: $0) ?? [] },
            draftRoomIds: {
                let merges = client?.mergedChats?.document ?? MergedChatDocument()
                return client?.composerDrafts.drafts.roomIds(merges: merges) ?? []
            }
        )
    }
}

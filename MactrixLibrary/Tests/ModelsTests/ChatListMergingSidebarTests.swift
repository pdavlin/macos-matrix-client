import Foundation
@testable import Models
import Testing

/// MATRIX-141 Phase B: the sidebar's list with merged chats. Filter (hidden
/// labels), then merge, then split favourites.
struct ChatListMergingSidebarTests {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)

    private static let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"])

    private static let labels = ChatLabelDocument(labels: [
        ChatLabel(id: "work", name: "Work", rooms: ["!s1", "!w1"]),
        ChatLabel(id: "fam", name: "Family", inboxVisibility: .hidden, rooms: ["!s2", "!f1"]),
    ])

    private func makeEntry(
        _ id: String,
        minutesAgo: Double,
        count: UInt64 = 0,
        isFavourite: Bool = false
    ) -> ChatListEntry {
        ChatListEntry(
            row: ChatListRowModel(
                id: id,
                title: "Title \(id)",
                isDirect: true,
                preview: "Preview \(id)",
                unread: ChatListUnread(count: count, isUnread: count > 0)
            ),
            lastActivity: Self.base.addingTimeInterval(-minutesAgo * 60),
            isFavourite: isFavourite
        )
    }

    private func sidebar(
        _ entries: [ChatListEntry],
        labels: ChatLabelDocument = labels,
        selectedLabelId: String? = nil,
        merges: [MergedChat] = [seth]
    ) -> VisibleChatList<ChatListItem> {
        ChatListMerging.visible(
            entries: entries,
            labels: labels,
            selectedLabelId: selectedLabelId,
            document: MergedChatDocument(merges: merges)
        )
    }

    // MARK: Filter, then merge

    @Test
    func inboxMergesMembersIntoOneRowInRecencyOrder() {
        let list = sidebar([
            makeEntry("!a", minutesAgo: 1),
            makeEntry("!s1", minutesAgo: 2),
            makeEntry("!b", minutesAgo: 3),
        ], labels: ChatLabelDocument())
        #expect(list.ordered.map(\.id) == ["!a", "m-seth", "!b"])
    }

    @Test
    func inboxDropsHiddenLabelRoomsBeforeMerging() throws {
        // !s2 is in the hidden Family label: the merged row shows for !s1 and
        // counts only !s1.
        let list = sidebar([
            makeEntry("!s2", minutesAgo: 1, count: 5),
            makeEntry("!s1", minutesAgo: 2, count: 2),
            makeEntry("!f1", minutesAgo: 3),
        ])
        #expect(list.ordered.map(\.id) == ["m-seth"])
        let merged = try #require(list.ordered.first?.mergedChat)
        #expect(merged.memberRoomIds == ["!s1"])
        #expect(merged.row.unread.count == 2)
    }

    @Test
    func mergedChatWithEveryMemberHiddenLeavesTheInbox() {
        let hiddenSeth = ChatLabelDocument(labels: [
            ChatLabel(id: "fam", name: "Family", inboxVisibility: .hidden, rooms: ["!s1", "!s2"]),
        ])
        let list = sidebar([
            makeEntry("!s1", minutesAgo: 1),
            makeEntry("!s2", minutesAgo: 2),
            makeEntry("!a", minutesAgo: 3),
        ], labels: hiddenSeth)
        #expect(list.ordered.map(\.id) == ["!a"])
    }

    @Test
    func selectedHiddenLabelShowsItsMergedRow() throws {
        // The SDK narrows the rooms to the label's set, so only !s2 and !f1
        // arrive; the label's own rooms are never hidden.
        let list = sidebar([
            makeEntry("!f1", minutesAgo: 1),
            makeEntry("!s2", minutesAgo: 2, count: 1),
        ], selectedLabelId: "fam")
        #expect(list.ordered.map(\.id) == ["!f1", "m-seth"])
        let merged = try #require(list.ordered.last?.mergedChat)
        #expect(merged.memberRoomIds == ["!s2"])
    }

    @Test
    func unknownSelectedLabelCountsAsTheInbox() {
        let list = sidebar([
            makeEntry("!f1", minutesAgo: 1),
            makeEntry("!a", minutesAgo: 2),
        ], selectedLabelId: "deleted")
        #expect(list.ordered.map(\.id) == ["!a"])
    }

    // MARK: Then split favourites

    @Test
    func mergedChatIsPinnedWhenAnyMemberIsAFavourite() {
        let list = sidebar([
            makeEntry("!a", minutesAgo: 1),
            makeEntry("!s1", minutesAgo: 2),
            makeEntry("!fav", minutesAgo: 3, isFavourite: true),
            makeEntry("!s2", minutesAgo: 4, isFavourite: true),
        ], labels: ChatLabelDocument())
        #expect(list.favorites.map(\.id) == ["m-seth", "!fav"])
        #expect(list.list.map(\.id) == ["!a"])
        // The grid comes first in the Go menu's walk, and the merged chat is
        // one step.
        #expect(list.ordered.map(\.id) == ["m-seth", "!fav", "!a"])
    }

    @Test
    func noMergesGivesTheSameSplitAsBeforeMergedChats() {
        let entries = [
            makeEntry("!a", minutesAgo: 1),
            makeEntry("!fav", minutesAgo: 2, isFavourite: true),
            makeEntry("!f1", minutesAgo: 3),
            makeEntry("!b", minutesAgo: 4),
        ]
        let merged = sidebar(entries, merges: [])
        let plain = VisibleChatList.visible(rooms: entries, labels: Self.labels, selectedLabelId: nil, isFavourite: \.isFavourite)
        #expect(merged.favorites.map(\.id) == plain.favorites.map(\.id))
        #expect(merged.list.map(\.id) == plain.list.map(\.id))
    }

    // MARK: One merged entry

    @Test
    func entryForAMergeIgnoresOtherRoomsAndRepeats() throws {
        let built = try #require(ChatListMerging.entry(for: Self.seth, members: [
            makeEntry("!other", minutesAgo: 1),
            makeEntry("!s2", minutesAgo: 2),
            makeEntry("!s1", minutesAgo: 3),
            makeEntry("!s2", minutesAgo: 4),
        ]))
        #expect(built.id == "m-seth")
        #expect(built.memberRoomIds == ["!s1", "!s2"])
        #expect(built.row.title == "Seth")
    }

    @Test
    func entryForAMergeWithNoKnownMemberIsNil() {
        #expect(ChatListMerging.entry(for: Self.seth, members: [makeEntry("!other", minutesAgo: 1)]) == nil)
    }
}

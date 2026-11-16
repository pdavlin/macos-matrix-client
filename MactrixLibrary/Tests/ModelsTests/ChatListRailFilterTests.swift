import Foundation
@testable import Models
import Testing

/// MATRIX-167: the rail's one filter for the Inbox, a space, and a label.
struct ChatListRailFilterTests {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)

    private static let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"])

    private static let labels = ChatLabelDocument(labels: [
        ChatLabel(id: "work", name: "Work", rooms: ["!s1", "!w1"]),
        ChatLabel(id: "fam", name: "Family", inboxVisibility: .hidden, rooms: ["!s2", "!f1"]),
    ])

    /// Two top-level spaces. `!both` is in both. `!deep` is in `!sub`, a
    /// sub-space of `!dev`.
    private static let spaces = RoomSpaceMap(parents: [
        "!s1": ["!dev"],
        "!w1": ["!dev"],
        "!f1": ["!pizza"],
        "!both": ["!dev", "!pizza"],
        "!deep": ["!sub"],
        "!sub": ["!dev"],
        "!a": [],
    ])

    private static let allIds = ["!a", "!s1", "!s2", "!w1", "!f1", "!both", "!deep"]

    private func makeEntry(_ id: String, minutesAgo: Double, count: UInt64 = 0, isFavourite: Bool = false) -> ChatListEntry {
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

    private var everyEntry: [ChatListEntry] {
        Self.allIds.enumerated().map { offset, id in makeEntry(id, minutesAgo: Double(offset + 1)) }
    }

    private func shownIds(_ filter: ChatListRailFilter, entries: [ChatListEntry]? = nil) -> [String] {
        ChatListMerging.visible(
            entries: entries ?? everyEntry,
            filter: filter,
            labels: Self.labels,
            spaces: Self.spaces,
            document: MergedChatDocument(merges: [Self.seth])
        ).ordered.map(\.id)
    }

    // MARK: The filter

    @Test
    func inboxDropsTheRoomsOfHiddenLabels() {
        #expect(shownIds(.inbox) == ["!a", "m-seth", "!w1", "!both", "!deep"])
    }

    @Test
    func labelShowsItsRoomsAlsoWhenHiddenFromTheInbox() {
        #expect(shownIds(.label("fam")) == ["m-seth", "!f1"])
        #expect(shownIds(.label("work")) == ["m-seth", "!w1"])
    }

    @Test
    func unknownLabelCountsAsTheInbox() {
        #expect(shownIds(.label("deleted")) == shownIds(.inbox))
    }

    @Test
    func spaceShowsItsChats() {
        #expect(shownIds(.space("!pizza")) == ["!f1", "!both"])
    }

    @Test
    func spaceShowsTheChatsOfItsSubSpaces() {
        #expect(shownIds(.space("!dev")) == ["m-seth", "!w1", "!both", "!deep"])
        #expect(shownIds(.space("!sub")) == ["!deep"])
    }

    @Test
    func chatInTwoSpacesShowsUnderBoth() {
        #expect(shownIds(.space("!dev")).contains("!both"))
        #expect(shownIds(.space("!pizza")).contains("!both"))
    }

    @Test
    func spaceShowsAChatOfALabelHiddenFromTheInbox() {
        // !f1 is in the hidden Family label and in the pizza space.
        #expect(!shownIds(.inbox).contains("!f1"))
        #expect(shownIds(.space("!pizza")).contains("!f1"))
    }

    @Test
    func mergedChatShowsUnderASpaceWhenAnyMemberIsInIt() throws {
        // Only !s1 is in the dev space: the merged row shows and counts !s1.
        let list = ChatListMerging.visible(
            entries: [makeEntry("!s2", minutesAgo: 1, count: 5), makeEntry("!s1", minutesAgo: 2, count: 2)],
            filter: .space("!dev"),
            labels: ChatLabelDocument(),
            spaces: Self.spaces,
            document: MergedChatDocument(merges: [Self.seth])
        )
        #expect(list.ordered.map(\.id) == ["m-seth"])
        let merged = try #require(list.ordered.first?.mergedChat)
        #expect(merged.memberRoomIds == ["!s1"])
        #expect(merged.row.unread.count == 2)
    }

    @Test
    func mergedChatWithNoMemberInTheSpaceIsNotShown() {
        #expect(!shownIds(.space("!pizza")).contains("m-seth"))
    }

    @Test
    func unknownSpaceShowsNothingUntilItIsResolved() {
        #expect(shownIds(.space("!gone")).isEmpty)
    }

    @Test
    func spaceFilterKeepsTheFavouritesSplit() {
        let list = ChatListMerging.visible(
            entries: [makeEntry("!w1", minutesAgo: 1), makeEntry("!both", minutesAgo: 2, isFavourite: true)],
            filter: .space("!dev"),
            labels: ChatLabelDocument(),
            spaces: Self.spaces,
            document: MergedChatDocument()
        )
        #expect(list.favorites.map(\.id) == ["!both"])
        #expect(list.list.map(\.id) == ["!w1"])
    }

    @Test
    func labelPathIsTheOldLabelFunction() {
        let old = ChatListMerging.visible(
            entries: everyEntry,
            labels: Self.labels,
            selectedLabelId: "work",
            document: MergedChatDocument(merges: [Self.seth])
        )
        #expect(old.ordered.map(\.id) == shownIds(.label("work")))
    }

    // MARK: Resolution

    @Test
    func resolvedKeepsWhatTheRailHolds() {
        #expect(ChatListRailFilter.inbox.resolved(labels: Self.labels, spaceIds: []) == .inbox)
        #expect(ChatListRailFilter.label("work").resolved(labels: Self.labels, spaceIds: []) == .label("work"))
        #expect(ChatListRailFilter.space("!dev").resolved(labels: Self.labels, spaceIds: ["!dev"]) == .space("!dev"))
    }

    @Test
    func resolvedTurnsAnUnknownSpaceOrLabelIntoTheInbox() {
        #expect(ChatListRailFilter.space("!gone").resolved(labels: Self.labels, spaceIds: ["!dev"]) == .inbox)
        // The space graph is not loaded yet at launch.
        #expect(ChatListRailFilter.space("!dev").resolved(labels: Self.labels, spaceIds: []) == .inbox)
        #expect(ChatListRailFilter.label("deleted").resolved(labels: Self.labels, spaceIds: ["!dev"]) == .inbox)
    }

    @Test
    func selectionAccessors() {
        #expect(ChatListRailFilter.label("work").labelId == "work")
        #expect(ChatListRailFilter.label("work").spaceId == nil)
        #expect(ChatListRailFilter.space("!dev").spaceId == "!dev")
        #expect(ChatListRailFilter.space("!dev").labelId == nil)
        #expect(ChatListRailFilter.inbox.labelId == nil)
        #expect(ChatListRailFilter.inbox.spaceId == nil)
    }

    // MARK: Room IDs

    private func roomIds(_ filter: ChatListRailFilter) -> [String] {
        ChatListMerging.roomIds(
            entries: everyEntry,
            filter: filter,
            labels: Self.labels,
            spaces: Self.spaces,
            document: MergedChatDocument(merges: [Self.seth])
        )
    }

    @Test
    func roomIdsOfASpaceAreItsChatsWithMergedMembersInIt() {
        #expect(roomIds(.space("!dev")) == ["!s1", "!w1", "!both", "!deep"])
        #expect(roomIds(.space("!pizza")) == ["!f1", "!both"])
    }

    @Test
    func roomIdsOfALabelAndOfTheInbox() {
        #expect(roomIds(.label("fam")) == ["!s2", "!f1"])
        #expect(roomIds(.inbox) == ["!a", "!s1", "!w1", "!both", "!deep"])
        #expect(roomIds(.space("!gone")).isEmpty)
    }

    @Test
    func narrowingRoomIdsForTheSDK() {
        #expect(ChatListRailFilter.inbox.narrowingRoomIds(labels: Self.labels, spaces: Self.spaces, chatIds: Self.allIds) == nil)
        #expect(
            ChatListRailFilter.label("work").narrowingRoomIds(labels: Self.labels, spaces: Self.spaces, chatIds: Self.allIds)
                == ["!s1", "!w1"]
        )
        #expect(
            ChatListRailFilter.space("!dev").narrowingRoomIds(labels: Self.labels, spaces: Self.spaces, chatIds: Self.allIds)
                == ["!both", "!deep", "!s1", "!w1"]
        )
    }

    // MARK: The space map

    @Test
    func spaceIdsWalkUpAndStopAtALoop() {
        #expect(Self.spaces.spaceIds(of: "!deep") == ["!sub", "!dev"])
        #expect(Self.spaces.spaceIds(of: "!a").isEmpty)
        #expect(Self.spaces.spaceIds(of: "!unknown").isEmpty)
        let loop = RoomSpaceMap(parents: ["!x": ["!p"], "!p": ["!q"], "!q": ["!p"]])
        #expect(loop.spaceIds(of: "!x") == ["!p", "!q"])
    }

    // MARK: Rail items

    private static let joined = [
        ChatListRailSpace(id: "!dev", name: "DevObsessed", avatarUrl: "mxc://a/dev"),
        ChatListRailSpace(id: "!empty", name: "Empty"),
        ChatListRailSpace(id: "!pizza", name: "pizza box audit committee"),
    ]

    @Test
    func railShowsTheSpacesWithChatsInTheGivenOrder() {
        let items = ChatListRailSpace.items(joined: Self.joined, spaces: Self.spaces, chatIds: Self.allIds, unread: [:])
        #expect(items.map(\.id) == ["!dev", "!pizza"])
        #expect(items.map(\.badge) == [.none, .none])
        #expect(items.first?.avatarUrl == "mxc://a/dev")
    }

    @Test
    func railIsEmptyBeforeTheSpaceGraphLoads() {
        let items = ChatListRailSpace.items(joined: Self.joined, spaces: RoomSpaceMap(), chatIds: Self.allIds, unread: [:])
        #expect(items.isEmpty)
    }

    @Test
    func subSpaceIsNotARailItemAndCountsOnlyChats() {
        // !sub is a child of !dev, but it is not in `chatIds`.
        let items = ChatListRailSpace.items(
            joined: [ChatListRailSpace(id: "!dev", name: "Dev")],
            spaces: RoomSpaceMap(parents: ["!sub": ["!dev"]]),
            chatIds: ["!a"],
            unread: [:]
        )
        #expect(items.isEmpty)
    }

    @Test
    func railBadgeFollowsTheLabelRule() {
        let unread: [String: ChatListUnread] = [
            "!s1": ChatListUnread(count: 3, isUnread: true),
            "!deep": ChatListUnread(count: 1, isUnread: true),
            "!w1": ChatListUnread(count: 4, isUnread: true, isMuted: true),
            "!f1": ChatListUnread(count: 2, isUnread: true, isMutedByLabel: true),
        ]
        let items = ChatListRailSpace.items(joined: Self.joined, spaces: Self.spaces, chatIds: Self.allIds, unread: unread)
        // Two unread chats count in dev; the muted one does not.
        #expect(items.first?.badge == .count(2))
        // Pizza has only a chat muted by its label: a dot.
        #expect(items.last?.badge == .dot)
    }

    @Test
    func markedUnreadChatGivesADot() {
        let badge = ChatLabelBadge.badge(forRooms: ["!a"], unread: ["!a": ChatListUnread(isUnread: true)])
        #expect(badge == .dot)
        #expect(ChatLabelBadge.badge(forRooms: ["!a"], unread: [:]) == ChatLabelBadge.none)
    }

    @Test
    func monogramAndColorAreStable() {
        let space = ChatListRailSpace(id: "!dev", name: " devObsessed")
        #expect(space.monogram == "D")
        #expect(space.colorIndex(paletteCount: 12) == space.colorIndex(paletteCount: 12))
        #expect((0 ..< 12).contains(space.colorIndex(paletteCount: 12)))
        #expect(space.colorIndex(paletteCount: 0) == 0)
    }
}

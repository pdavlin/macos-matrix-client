import Foundation
@testable import Models
import Testing

/// MATRIX-172: the source of the broadcast targets. Every chat of the rail
/// filter that the account has, from the account's room list, with a gap
/// when the list cannot give them all.
struct BroadcastTargetListTests {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)
    private static let limit = 1000

    /// `!s1` and `!s2` are one merged chat. Its default room is `!s2`.
    private static let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"], defaultRoom: "!s2")
    private static let document = MergedChatDocument(merges: [seth])

    private static let labels = ChatLabelDocument(labels: [
        ChatLabel(id: "work", name: "Work", rooms: ["!s1", "!s2", "!w1", "!w2", "!w3"]),
    ])

    private static let spaces = RoomSpaceMap(parents: [
        "!s1": ["!dev"],
        "!w1": ["!dev"],
        "!w2": ["!dev"],
        "!deep": ["!sub"],
        "!sub": ["!dev"],
    ])

    /// Every chat of the account, as the unfiltered room list holds them.
    private static let account: Set<String> = ["!a", "!s1", "!s2", "!w1", "!w2", "!w3", "!deep"]

    private func makeEntry(_ id: String, minutesAgo: Double, isFavourite: Bool = false) -> ChatListEntry {
        ChatListEntry(
            row: ChatListRowModel(id: id, title: "Sidebar \(id)"),
            lastActivity: Self.base.addingTimeInterval(-minutesAgo * 60),
            isFavourite: isFavourite
        )
    }

    /// The row of a room the sidebar does not hold.
    private static func storeRow(_ id: String) -> ChatListRowModel? {
        ChatListRowModel(id: id, title: "Store \(id)")
    }

    private func makeList(
        _ filter: ChatListRailFilter,
        sidebar: [ChatListEntry],
        account: Set<String> = BroadcastTargetListTests.account,
        limit: Int = BroadcastTargetListTests.limit,
        row: @escaping (String) -> ChatListRowModel? = BroadcastTargetListTests.storeRow
    ) -> BroadcastTargetList {
        BroadcastTargetList.make(
            source: BroadcastChatSource(sidebarEntries: sidebar, accountChatIds: account, accountListLimit: limit, row: row),
            filter: filter,
            labels: Self.labels,
            spaces: Self.spaces,
            document: Self.document,
            now: Self.base
        )
    }

    // MARK: - Targets

    @Test func inboxGivesNoTargetAndNoGap() {
        #expect(makeList(.inbox, sidebar: [makeEntry("!a", minutesAgo: 1)]) == BroadcastTargetList())
    }

    @Test func unknownLabelGivesNoTargetAndNoGap() {
        #expect(makeList(.label("gone"), sidebar: [makeEntry("!a", minutesAgo: 1)]) == BroadcastTargetList())
    }

    /// The sidebar shows one chat of the label (an Unread filter, or one
    /// page). The targets are all the label's chats: the sidebar's first, in
    /// sidebar order, then the others by title.
    @Test func targetsDoNotDependOnTheChatsTheSidebarShows() {
        let list = makeList(.label("work"), sidebar: [makeEntry("!w2", minutesAgo: 1)])
        #expect(list.targets.map(\.id) == ["!w2", "m-seth", "!w1", "!w3"])
        #expect(list.targets.map(\.title) == ["Sidebar !w2", "Seth", "Store !w1", "Store !w3"])
        #expect(list.gap == nil)
    }

    @Test func emptySidebarStillGivesEveryChatOfTheFilter() {
        let list = makeList(.label("work"), sidebar: [])
        #expect(Set(list.targets.map(\.id)) == ["m-seth", "!w1", "!w2", "!w3"])
        #expect(list.gap == nil)
    }

    /// A sidebar chat outside the filter is no target.
    @Test func sidebarChatOutsideTheFilterIsNoTarget() {
        let list = makeList(.label("work"), sidebar: [makeEntry("!a", minutesAgo: 1), makeEntry("!w1", minutesAgo: 2)])
        #expect(!list.targets.contains { $0.id == "!a" })
        #expect(list.targets.first?.id == "!w1")
    }

    /// A merged chat is one target and goes to its default room, also when
    /// the sidebar holds one member only.
    @Test func mergedChatIsOneTarget() throws {
        let list = makeList(.label("work"), sidebar: [makeEntry("!s1", minutesAgo: 1)])
        let merged = try #require(list.targets.first { $0.id == "m-seth" })
        #expect(merged.roomId == "!s2")
        #expect(list.targets.filter { $0.mergedChatId == "m-seth" }.count == 1)
    }

    /// The rooms of the targets are rooms of `ChatListMerging.roomIds`, and
    /// each chat of `roomIds` has its target.
    @Test func targetsAgreeWithChatListMergingRoomIds() {
        let sidebar = [makeEntry("!w2", minutesAgo: 1)]
        let list = makeList(.space("!dev"), sidebar: sidebar)
        let others = ["!deep", "!s1", "!w1"].map { ChatListEntry(row: ChatListRowModel(id: $0, title: "Store \($0)")) }
        let roomIds = ChatListMerging.roomIds(
            entries: sidebar + others, filter: .space("!dev"), labels: Self.labels, spaces: Self.spaces, document: Self.document
        )
        #expect(list.targets.map(\.roomId) == roomIds)
        #expect(roomIds == ["!w2", "!deep", "!s1", "!w1"])
    }

    /// A space holds the chats of its sub-spaces. A space is no target.
    @Test func spaceTargetsComeFromTheAccountList() {
        let list = makeList(.space("!dev"), sidebar: [])
        #expect(list.targets.map(\.roomId) == ["!deep", "!s1", "!w1", "!w2"])
        #expect(list.gap == nil)
    }

    @Test func aRoomInBothListsIsOneTarget() {
        let list = makeList(.label("work"), sidebar: [makeEntry("!w1", minutesAgo: 1), makeEntry("!w1", minutesAgo: 2)])
        #expect(list.targets.filter { $0.id == "!w1" }.count == 1)
    }

    // MARK: - Gap

    /// The label names two rooms that no list holds.
    @Test func labelRoomsOutsideTheAccountListAreCounted() {
        let list = makeList(.label("work"), sidebar: [], account: ["!s1", "!s2", "!w1"])
        #expect(Set(list.targets.map(\.id)) == ["m-seth", "!w1"])
        #expect(list.gap == BroadcastTargetGap(reason: .notInAccountList, count: 2))
    }

    /// The account list is empty: the targets are the sidebar's chats, and
    /// the label gives the number of the others.
    @Test func emptyAccountListWithALabelCountsTheMissingChats() {
        let list = makeList(.label("work"), sidebar: [makeEntry("!w1", minutesAgo: 1)], account: [])
        #expect(list.targets.map(\.id) == ["!w1"])
        #expect(list.gap == BroadcastTargetGap(reason: .accountListNotLoaded, count: 4))
    }

    /// The sidebar holds every room of the label, so nothing is missing.
    @Test func emptyAccountListWithACompleteLabelHasNoGap() {
        let sidebar = ["!s1", "!s2", "!w1", "!w2", "!w3"].enumerated().map { makeEntry($1, minutesAgo: Double($0)) }
        let list = makeList(.label("work"), sidebar: sidebar, account: [])
        #expect(list.targets.count == 4)
        #expect(list.gap == nil)
    }

    /// A space names its chats only through the room list: no count.
    @Test func emptyAccountListWithASpaceHasAGapWithoutCount() {
        let list = makeList(.space("!dev"), sidebar: [makeEntry("!w1", minutesAgo: 1)], account: [])
        #expect(list.targets.map(\.id) == ["!w1"])
        #expect(list.gap == BroadcastTargetGap(reason: .accountListNotLoaded, count: nil))
    }

    @Test func fullAccountListWithASpaceHasAGapWithoutCount() {
        let list = makeList(.space("!dev"), sidebar: [], limit: Self.account.count)
        #expect(list.targets.count == 4)
        #expect(list.gap == BroadcastTargetGap(reason: .accountListFull(limit: Self.account.count), count: nil))
    }

    @Test func fullAccountListWithALabelCountsTheMissingChats() {
        let list = makeList(.label("work"), sidebar: [], account: ["!s1", "!s2", "!w1", "!w2"], limit: 4)
        #expect(list.gap == BroadcastTargetGap(reason: .accountListFull(limit: 4), count: 1))
    }

    @Test func fullAccountListWithACompleteLabelHasNoGap() {
        #expect(makeList(.label("work"), sidebar: [], limit: Self.account.count).gap == nil)
    }

    /// The client has no data for a room of the account list: no target,
    /// and the room is counted.
    @Test func roomWithoutRowIsMissing() {
        let list = makeList(.space("!dev"), sidebar: []) { id in
            id == "!w2" ? nil : Self.storeRow(id)
        }
        #expect(!list.targets.contains { $0.id == "!w2" })
        #expect(list.gap == BroadcastTargetGap(reason: .notInAccountList, count: 1))
    }

    // MARK: - Lines

    @Test func sourceLineOfACompleteList() {
        let targets = (0 ..< 132).map { index in
            BroadcastTarget(id: "!r\(index)", row: ChatListRowModel(id: "!r\(index)", title: "Chat"), roomId: "!r\(index)")
        }
        #expect(BroadcastTargetList(targets: targets).sourceLine(filterName: "DevObsessed") == "All 132 chats of DevObsessed")
        #expect(BroadcastTargetList(targets: [targets[0]]).sourceLine(filterName: "Work") == "The 1 chat of Work")
    }

    /// A list with a gap does not say "All".
    @Test func sourceLineOfAListWithAGap() {
        let target = BroadcastTarget(id: "!r", row: ChatListRowModel(id: "!r", title: "Chat"), roomId: "!r")
        let gap = BroadcastTargetGap(reason: .accountListNotLoaded, count: nil)
        #expect(BroadcastTargetList(targets: [target, target], gap: gap).sourceLine(filterName: "Work") == "2 chats of Work")
        #expect(BroadcastTargetList(targets: [target], gap: gap).sourceLine(filterName: "Work") == "1 chat of Work")
    }

    @Test func gapLines() {
        #expect(BroadcastTargetGap(reason: .accountListNotLoaded, count: nil).line
            == "Some chats can be missing because the full chat list is not loaded.")
        #expect(BroadcastTargetGap(reason: .accountListNotLoaded, count: 4).line
            == "4 chats are missing because the full chat list is not loaded.")
        #expect(BroadcastTargetGap(reason: .accountListFull(limit: 1000), count: nil).line
            == "Some chats can be missing because the full chat list holds 1000 chats at most.")
        #expect(BroadcastTargetGap(reason: .accountListFull(limit: 1000), count: 1).line
            == "1 chat is missing because the full chat list holds 1000 chats at most.")
        #expect(BroadcastTargetGap(reason: .notInAccountList, count: 1).line
            == "1 chat is missing because the full chat list does not hold it. It is not joined, or not loaded yet.")
        #expect(BroadcastTargetGap(reason: .notInAccountList, count: 3).line
            == "3 chats are missing because the full chat list does not hold them. They are not joined, or not loaded yet.")
    }
}

import Foundation
import Models
import Testing

/// MATRIX-247: the iOS chat search reuses the ⌘K ranking, and a tap opens
/// the room that ⌘K opens.
struct ChatListSearchTests {
    private let rooms = [
        QuickSwitcherRoom(id: "!eng", name: "Engineering", canonicalAlias: "#eng:example.org", recencyRank: 0),
        QuickSwitcherRoom(id: "!alice", name: "Alice", isDirect: true, directUserId: "@alice:example.org", recencyRank: 1),
        QuickSwitcherRoom(id: "!design", name: "Product Design", recencyRank: 2),
    ]

    @Test func blankQueryShowsTheList() {
        #expect(ChatListSearch.results(in: rooms, query: "") == nil)
        #expect(ChatListSearch.results(in: rooms, query: "   ") == nil)
    }

    @Test func resultsFollowTheQuickSwitcherRanking() {
        let query = "e"
        let expected = QuickSwitcherRanking.rankRooms(rooms, query: query, currentRoomId: nil)

        #expect(ChatListSearch.results(in: rooms, query: query) == expected)
    }

    @Test func noMatchIsAnEmptyResult() {
        #expect(ChatListSearch.results(in: rooms, query: "xyz") == [])
    }

    @Test func findsARoomBeyondTheListPage() {
        // The chat list holds 100 rooms per page; the search covers every
        // room the directory has.
        var many = (0 ..< 150).map { QuickSwitcherRoom(id: "!r\($0)", name: "Room \($0)", recencyRank: $0) }
        many.append(QuickSwitcherRoom(id: "!old", name: "Book club", recencyRank: 150))

        #expect(ChatListSearch.results(in: many, query: "book")?.map(\.id) == ["!old"])
    }

    @Test func matchesTheAliasAndTheDirectPartner() {
        #expect(ChatListSearch.results(in: rooms, query: "#eng")?.first?.id == "!eng")
        #expect(ChatListSearch.results(in: rooms, query: "@alice")?.first?.id == "!alice")
    }

    @Test func keepsTheQuickSwitcherLimit() {
        let many = (0 ..< 40).map { QuickSwitcherRoom(id: "!r\($0)", name: "Room \($0)", recencyRank: $0) }

        #expect(ChatListSearch.results(in: many, query: "room")?.count == QuickSwitcherRanking.defaultRoomLimit)
    }

    @Test func aTapOpensTheRoomItself() {
        for room in rooms {
            #expect(ChatListSearch.roomToOpen(room) == room.id)
        }
    }
}

/// MATRIX-247: the iOS list filter menu offers the Inbox and Low Priority.
/// MATRIX-248: and Archived and Snoozed.
struct ChatListFilterIOSTests {
    @Test func offersInboxLowPriorityArchivedAndSnoozed() {
        #expect(ChatListFilter.iosChoices == [.inbox, .lowPriority, .archived, .snoozed])
    }

    @Test func restoresAnOfferedFilter() {
        #expect(ChatListFilter.iosChoice(restoring: "lowPriority") == .lowPriority)
        #expect(ChatListFilter.iosChoice(restoring: "inbox") == .inbox)
        #expect(ChatListFilter.iosChoice(restoring: "archived") == .archived)
        #expect(ChatListFilter.iosChoice(restoring: "snoozed") == .snoozed)
    }

    @Test func restoresTheInboxForAnythingElse() {
        #expect(ChatListFilter.iosChoice(restoring: nil) == .inbox)
        #expect(ChatListFilter.iosChoice(restoring: "unread") == .inbox)
        #expect(ChatListFilter.iosChoice(restoring: "drafts") == .inbox)
        #expect(ChatListFilter.iosChoice(restoring: "no such filter") == .inbox)
    }

    @Test func listTitleNamesTheFilter() {
        #expect(ChatListFilter.inbox.iosListTitle == "Chats")
        #expect(ChatListFilter.lowPriority.iosListTitle == "Low Priority")
        #expect(ChatListFilter.archived.iosListTitle == "Archived")
        #expect(ChatListFilter.snoozed.iosListTitle == "Snoozed")
    }
}

/// MATRIX-248: a merged chat is one search result that opens its newest
/// member room, the merged chat's name matches, and archived and snoozed
/// chats carry the ⌘K mark.
struct ChatListSearchMergedTests {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)

    /// Seth on Signal (older) and on WhatsApp (newer), merged as "Seth M.".
    private let rooms = [
        QuickSwitcherRoom(id: "!eng", name: "Engineering", recencyRank: 0),
        QuickSwitcherRoom(id: "!seth-wa", name: "Seth (WhatsApp)", avatarUrl: "mxc://wa", isDirect: true, recencyRank: 1),
        QuickSwitcherRoom(id: "!sam", name: "Sam", isDirect: true, recencyRank: 2),
        QuickSwitcherRoom(id: "!seth-signal", name: "Seth (Signal)", isDirect: true, recencyRank: 3),
    ]
    private let merges = MergedChatDocument(merges: [
        MergedChat(id: "m-seth", name: "Seth M.", rooms: ["!seth-signal", "!seth-wa"]),
    ])

    @Test func aMemberRoomShowsAsItsMergedChat() throws {
        let results = try #require(ChatListSearch.results(in: rooms, query: "whatsapp", merges: merges))

        #expect(results.count == 1)
        #expect(results.first?.name == "Seth M.")
        #expect(results.first?.id == "!seth-wa")
    }

    @Test func membersThatBothMatchShowOnce() throws {
        let results = try #require(ChatListSearch.results(in: rooms, query: "seth", merges: merges))

        #expect(results.map(\.id) == ["!seth-wa"])
    }

    @Test func aTapOpensTheNewestMemberRoom() throws {
        // The Signal room matches, and the newer WhatsApp room opens.
        let result = try #require(ChatListSearch.results(in: rooms, query: "signal", merges: merges)?.first)

        #expect(ChatListSearch.roomToOpen(result) == "!seth-wa")
    }

    @Test func theMergedNameMatches() throws {
        let renamed = MergedChatDocument(merges: [MergedChat(id: "m-seth", name: "Brother", rooms: ["!seth-signal", "!seth-wa"])])

        let results = try #require(ChatListSearch.results(in: rooms, query: "brother", merges: renamed))

        #expect(results.map(\.name) == ["Brother"])
        #expect(results.map(\.id) == ["!seth-wa"])
    }

    @Test func plainRoomsKeepTheirResults() throws {
        let results = try #require(ChatListSearch.results(in: rooms, query: "s", merges: merges))

        #expect(Set(results.map(\.id)) == ["!seth-wa", "!sam"])
        #expect(results.first { $0.id == "!sam" }?.name == "Sam")
    }

    @Test func theLimitCountsAMergedChatOnce() throws {
        let results = try #require(ChatListSearch.results(in: rooms, query: "s", merges: merges, limit: 1))

        #expect(results.count == 1)
    }

    @Test func noMergesGiveTheQuickSwitcherRanking() {
        let expected = QuickSwitcherRanking.rankRooms(rooms, query: "s", currentRoomId: nil)

        #expect(ChatListSearch.results(in: rooms, query: "s") == expected)
    }

    @Test func archivedAndSnoozedResultsCarryTheMark() throws {
        let now = Self.base
        let until = now.addingTimeInterval(2 * 60 * 60)
        var inbox = InboxStateDocument()
        inbox.archive(["!eng"], at: now)
        inbox.snooze(["!seth-signal", "!seth-wa"], until: until, at: now)

        let results = try #require(ChatListSearch.results(in: rooms, query: "e", merges: merges, inbox: inbox, now: now))
        let marks = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0.detail) })

        #expect(marks["!eng"] == "Archived")
        #expect(marks["!seth-wa"] == InboxTimeText.snoozed(until: until, now: now))
    }

    @Test func inboxResultsHaveNoMark() throws {
        let results = try #require(ChatListSearch.results(in: rooms, query: "sam", merges: merges, inbox: InboxStateDocument()))

        #expect(results.first?.detail == nil)
    }
}

/// MATRIX-248: the merged chat's search result: the newest member room by
/// the SDK's recency order, with the merged name and avatar.
struct ChatListSearchMergedResultTests {
    @Test func newestMemberIsTheFirstInRecencyOrder() {
        let merge = MergedChat(id: "m", name: "Seth", rooms: ["!a", "!b", "!c"])
        let members = [
            QuickSwitcherRoom(id: "!a", name: "A", recencyRank: 9),
            QuickSwitcherRoom(id: "!b", name: "B", recencyRank: 2),
            QuickSwitcherRoom(id: "!c", name: "C", recencyRank: 5),
        ]

        let result = ChatListSearch.mergedResult(merge: merge, members: members)

        #expect(result?.id == "!b")
        #expect(result?.recencyRank == 2)
    }

    @Test func avatarFollowsTheMergedRowRule() {
        let members = [
            QuickSwitcherRoom(id: "!a", name: "A", recencyRank: 0),
            QuickSwitcherRoom(id: "!b", name: "B", avatarUrl: "mxc://b", isDirect: true, recencyRank: 1),
            QuickSwitcherRoom(id: "!c", name: "C", avatarUrl: "mxc://c", recencyRank: 2),
        ]

        let firstWithImage = ChatListSearch.mergedResult(
            merge: MergedChat(id: "m", name: "Seth", rooms: ["!a", "!b", "!c"]),
            members: members
        )
        let chosen = ChatListSearch.mergedResult(
            merge: MergedChat(id: "m", name: "Seth", rooms: ["!a", "!b", "!c"], avatarRoom: "!c"),
            members: members
        )

        #expect(firstWithImage?.avatarUrl == "mxc://b")
        #expect(firstWithImage?.isDirect == true)
        #expect(chosen?.avatarUrl == "mxc://c")
    }

    @Test func blankNameShowsTheAvatarMembersName() {
        let members = [QuickSwitcherRoom(id: "!a", name: "Seth (Signal)", recencyRank: 0)]

        let result = ChatListSearch.mergedResult(merge: MergedChat(id: "m", name: "  ", rooms: ["!a", "!b"]), members: members)

        #expect(result?.name == "Seth (Signal)")
    }

    @Test func noMemberGivesNoResult() {
        #expect(ChatListSearch.mergedResult(merge: MergedChat(id: "m", name: "Seth", rooms: ["!a"]), members: []) == nil)
    }
}

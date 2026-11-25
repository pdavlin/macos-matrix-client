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
struct ChatListFilterIOSTests {
    @Test func offersInboxAndLowPriority() {
        #expect(ChatListFilter.iosChoices == [.inbox, .lowPriority])
    }

    @Test func restoresAnOfferedFilter() {
        #expect(ChatListFilter.iosChoice(restoring: "lowPriority") == .lowPriority)
        #expect(ChatListFilter.iosChoice(restoring: "inbox") == .inbox)
    }

    @Test func restoresTheInboxForAnythingElse() {
        #expect(ChatListFilter.iosChoice(restoring: nil) == .inbox)
        #expect(ChatListFilter.iosChoice(restoring: "unread") == .inbox)
        #expect(ChatListFilter.iosChoice(restoring: "archived") == .inbox)
        #expect(ChatListFilter.iosChoice(restoring: "no such filter") == .inbox)
    }

    @Test func listTitleNamesTheFilter() {
        #expect(ChatListFilter.inbox.iosListTitle == "Chats")
        #expect(ChatListFilter.lowPriority.iosListTitle == "Low Priority")
    }
}

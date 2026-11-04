import Models
import Testing

/// MATRIX-114: fuzzy scoring for the ⌘K quick switcher.
struct QuickSwitcherFuzzyTests {
    private func score(_ query: String, _ candidate: String) -> Int? {
        QuickSwitcherFuzzy.score(query: query, candidate: candidate)
    }

    @Test func tiersOrderExactPrefixWordStartSubstringSubsequence() throws {
        let exact = try #require(score("design", "Design"))
        let prefix = try #require(score("design", "Design Team"))
        let wordStart = try #require(score("design", "Product Design"))
        let substring = try #require(score("sign", "Product Design"))
        let subsequence = try #require(score("pdn", "Product Design"))

        #expect(exact > prefix)
        #expect(prefix > wordStart)
        #expect(wordStart > substring)
        #expect(substring > subsequence)
        #expect(subsequence > 0)
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(score("CAFE", "Café") == score("cafe", "cafe"))
    }

    @Test func noMatchReturnsNil() {
        #expect(score("xyz", "Engineering") == nil)
        #expect(score("gne", "Engineering") != nil)
        #expect(score("engineeringx", "Engineering") == nil)
    }

    @Test func emptyOrBlankQueryReturnsNil() {
        #expect(score("", "Engineering") == nil)
        #expect(score("   ", "Engineering") == nil)
    }

    @Test func shorterCandidateWinsInsideATier() throws {
        let short = try #require(score("eng", "Engineering"))
        let long = try #require(score("eng", "Engineering and Operations"))
        #expect(short > long)
    }

    @Test func tightSubsequenceBeatsScatteredSubsequence() throws {
        let tight = try #require(score("prd", "Product Roadmap Discussion"))
        let scattered = try #require(score("ptn", "Product Roadmap Discussion"))
        #expect(tight > scattered)
    }

    @Test func aliasPunctuationStartsAWord() throws {
        // "#matrix:matrix.org": the first "matrix" follows "#", so it is a
        // word start, not a mid-word substring.
        let aliasScore = try #require(score("matrix", "#matrix:matrix.org"))
        let midWord = try #require(score("trix", "#matrix:matrix.org"))
        #expect(aliasScore > midWord)
    }
}

/// MATRIX-114: ranking, merging, dedupe, and the activation decision.
struct QuickSwitcherRankingTests {
    private let general = QuickSwitcherRoom(id: "!general", name: "General", canonicalAlias: "#general:example.org", recencyRank: 2)
    private let random = QuickSwitcherRoom(id: "!random", name: "Random", canonicalAlias: "#random:example.org", recencyRank: 0)
    private let design = QuickSwitcherRoom(id: "!design", name: "Design Reviews", canonicalAlias: "#crit:example.org", recencyRank: 3)
    private let aliceDM = QuickSwitcherRoom(
        id: "!alice", name: "Alice Liddell", isDirect: true, directUserId: "@alice:example.org", recencyRank: 1
    )

    private var rooms: [QuickSwitcherRoom] {
        [general, random, design, aliceDM]
    }

    // MARK: Ranking

    @Test func emptyQueryListsRoomsByRecency() {
        let ranked = QuickSwitcherRanking.rankRooms(rooms, query: "", currentRoomId: nil)
        #expect(ranked.map(\.id) == ["!random", "!alice", "!general", "!design"])
    }

    @Test func emptyQueryMovesTheCurrentRoomToTheEnd() {
        let ranked = QuickSwitcherRanking.rankRooms(rooms, query: "  ", currentRoomId: "!random")
        #expect(ranked.map(\.id) == ["!alice", "!general", "!design", "!random"])
    }

    @Test func emptyQueryHonoursTheLimit() {
        let ranked = QuickSwitcherRanking.rankRooms(rooms, query: "", currentRoomId: nil, limit: 2)
        #expect(ranked.map(\.id) == ["!random", "!alice"])
    }

    @Test func queryKeepsOnlyMatchesBestFirst() {
        let ranked = QuickSwitcherRanking.rankRooms(rooms, query: "gen", currentRoomId: nil)
        #expect(ranked.map(\.id) == ["!general"])
    }

    @Test func aliasMatchesWhenTheNameDoesNot() {
        let ranked = QuickSwitcherRanking.rankRooms(rooms, query: "crit", currentRoomId: nil)
        #expect(ranked.map(\.id) == ["!design"])
    }

    @Test func dmPartnerUserIdMatches() {
        let ranked = QuickSwitcherRanking.rankRooms(rooms, query: "@alice", currentRoomId: nil)
        #expect(ranked.map(\.id) == ["!alice"])
    }

    @Test func nameMatchBeatsTheSameMatchOnAnAlias() {
        let byName = QuickSwitcherRoom(id: "!a", name: "ops", recencyRank: 5)
        let byAlias = QuickSwitcherRoom(id: "!b", name: "Infrastructure", canonicalAlias: "ops", recencyRank: 0)
        let ranked = QuickSwitcherRanking.rankRooms([byAlias, byName], query: "ops", currentRoomId: nil)
        #expect(ranked.map(\.id) == ["!a", "!b"])
    }

    @Test func recencyBreaksScoreTies() {
        let older = QuickSwitcherRoom(id: "!older", name: "Team", recencyRank: 9)
        let newer = QuickSwitcherRoom(id: "!newer", name: "Team", recencyRank: 1)
        let ranked = QuickSwitcherRanking.rankRooms([older, newer], query: "team", currentRoomId: nil)
        #expect(ranked.map(\.id) == ["!newer", "!older"])
    }

    // MARK: Merge and dedupe

    @Test func emptyQueryListsRoomsOnly() {
        let rows = QuickSwitcherRanking.merge(
            rankedRooms: [random], query: "", directoryResults: [NewChatPerson(userId: "@bob:example.org")],
            ownUserId: nil, mode: .navigate
        )
        #expect(rows == [.room(random)])
    }

    @Test func peopleFollowRoomsAndSkipListedDMPartners() {
        let alice = NewChatPerson(userId: "@alice:example.org", displayName: "Alice Liddell")
        let alan = NewChatPerson(userId: "@alan:example.org", displayName: "Alan")
        let rows = QuickSwitcherRanking.merge(
            rankedRooms: [aliceDM], query: "al", directoryResults: [alice, alan],
            ownUserId: nil, mode: .navigate
        )
        #expect(rows == [.room(aliceDM), .person(alan)])
    }

    @Test func aDMPartnerWhoseRoomIsNotListedStillShowsAsAPerson() {
        let alice = NewChatPerson(userId: "@alice:example.org", displayName: "Alice Liddell")
        let rows = QuickSwitcherRanking.merge(
            rankedRooms: [], query: "liddell", directoryResults: [alice],
            ownUserId: nil, mode: .navigate
        )
        #expect(rows == [.person(alice)])
    }

    @Test func mergeDropsTheOwnUserAndDuplicates() {
        let me = NewChatPerson(userId: "@me:example.org")
        let bob = NewChatPerson(userId: "@bob:example.org", displayName: "Bob")
        let rows = QuickSwitcherRanking.merge(
            rankedRooms: [], query: "b", directoryResults: [me, bob, bob],
            ownUserId: "@me:example.org", mode: .navigate
        )
        #expect(rows == [.person(bob)])
    }

    @Test func staleDirectoryResultsThatNoLongerMatchAreDropped() {
        // Results for "bo" are still on screen while "bob" is searched.
        let bob = NewChatPerson(userId: "@bob:example.org", displayName: "Bob")
        let boris = NewChatPerson(userId: "@boris:example.org", displayName: "Boris")
        let rows = QuickSwitcherRanking.merge(
            rankedRooms: [], query: "bob", directoryResults: [bob, boris],
            ownUserId: nil, mode: .navigate
        )
        #expect(rows == [.person(bob)])
    }

    @Test func exactUserIdGetsARowWithoutADirectoryHit() {
        let rows = QuickSwitcherRanking.merge(
            rankedRooms: [], query: "@slackbot:example.org", directoryResults: [],
            ownUserId: nil, mode: .navigate
        )
        #expect(rows == [.person(NewChatPerson(userId: "@slackbot:example.org"))])
    }

    @Test func roomAndPersonIdsNeverCollide() {
        let room = QuickSwitcherResult.room(QuickSwitcherRoom(id: "x", name: "x", recencyRank: 0))
        let person = QuickSwitcherResult.person(NewChatPerson(userId: "x"))
        #expect(room.id != person.id)
    }

    // MARK: Picker mode

    @Test func pickerModeListsRoomsOnlyAndNeverSearches() {
        let rows = QuickSwitcherRanking.merge(
            rankedRooms: [general], query: "gen", directoryResults: [NewChatPerson(userId: "@gene:example.org")],
            ownUserId: nil, mode: .pickRoom
        )
        #expect(rows == [.room(general)])
        #expect(!QuickSwitcherRanking.shouldSearchDirectory(query: "gen", mode: .pickRoom))
        #expect(QuickSwitcherRanking.shouldSearchDirectory(query: "gen", mode: .navigate))
        #expect(!QuickSwitcherRanking.shouldSearchDirectory(query: " ", mode: .navigate))
    }

    @Test func pickerModeReturnsTheRoomForEitherKey() {
        #expect(QuickSwitcherRanking.decide(.room(general), mode: .pickRoom, key: .primary) == .pickRoom(roomId: "!general"))
        #expect(QuickSwitcherRanking.decide(.room(general), mode: .pickRoom, key: .alternate) == .pickRoom(roomId: "!general"))
        #expect(QuickSwitcherRanking.decide(.person(NewChatPerson(userId: "@a:b")), mode: .pickRoom, key: .primary) == .ignore)
    }

    // MARK: Navigate mode decisions

    @Test func navigateModeOpensRoomsAndStartsDirectChats() {
        let bob = NewChatPerson(userId: "@bob:example.org")
        #expect(QuickSwitcherRanking.decide(.room(general), mode: .navigate, key: .primary) == .openRoom(roomId: "!general"))
        #expect(QuickSwitcherRanking.decide(.person(bob), mode: .navigate, key: .primary) == .startDirectChat(userId: "@bob:example.org"))
    }

    @Test func optionReturnIsReservedForANewWindow() {
        let bob = NewChatPerson(userId: "@bob:example.org")
        #expect(
            QuickSwitcherRanking.decide(.room(general), mode: .navigate, key: .alternate)
                == .openRoomInNewWindow(roomId: "!general")
        )
        #expect(QuickSwitcherRanking.decide(.person(bob), mode: .navigate, key: .alternate) == .ignore)
    }
}

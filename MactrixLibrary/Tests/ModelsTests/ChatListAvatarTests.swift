@testable import Models
import Testing

/// MATRIX-129: the chat-list avatar rules (choice, hero filter, cluster
/// layout, initials, and the palette hash).
struct ChatListAvatarTests {
    private let alice = ChatListHero(userId: "@alice:example.org", displayName: "Alice Liddell", avatarUrl: "mxc://example.org/alice")
    private let bob = ChatListHero(userId: "@bob:example.org", displayName: "Bob Ross")
    private let carol = ChatListHero(userId: "@carol:example.org", displayName: "Carol")
    private let dan = ChatListHero(userId: "@dan:example.org", displayName: "Dan")
    private let erin = ChatListHero(userId: "@erin:example.org", displayName: "Erin")

    private var fiveHeroes: [ChatListHero] {
        [alice, bob, carol, dan, erin]
    }

    // MARK: Avatar choice

    /// `ChatListAvatarChoice.choose` for a room without its own avatar.
    private func choose(roomId: String, title: String, isDirect: Bool, heroes: [ChatListHero]) -> ChatListAvatarChoice {
        ChatListAvatarChoice.choose(roomId: roomId, title: title, avatarUrl: nil, isDirect: isDirect, heroes: heroes)
    }

    @Test
    func roomAvatarWinsOverEverything() {
        let choice = ChatListAvatarChoice.choose(
            roomId: "!g:example.org",
            title: "Book club",
            avatarUrl: "mxc://example.org/room",
            isDirect: false,
            heroes: [alice, bob, carol]
        )
        #expect(choice == .image(url: "mxc://example.org/room", placeholder: .room(title: "Book club", roomId: "!g:example.org")))
    }

    @Test
    func directRoomAvatarKeepsThePersonInitialsAsPlaceholder() {
        let choice = ChatListAvatarChoice.choose(
            roomId: "!dm:example.org",
            title: "Bob Ross",
            avatarUrl: "mxc://example.org/room",
            isDirect: true,
            heroes: [bob]
        )
        #expect(choice == .image(url: "mxc://example.org/room", placeholder: .person(displayName: "Bob Ross", userId: bob.userId)))
    }

    @Test
    func directChatWithoutRoomAvatarUsesTheHeroAvatar() {
        let choice = ChatListAvatarChoice.choose(
            roomId: "!dm:example.org",
            title: "Alice Liddell",
            avatarUrl: nil,
            isDirect: true,
            heroes: [alice]
        )
        #expect(choice == .image(url: "mxc://example.org/alice", placeholder: .person(displayName: "Alice Liddell", userId: alice.userId)))
    }

    @Test
    func directChatWithHeroWithoutAvatarUsesPersonInitials() {
        let choice = choose(roomId: "!dm:example.org", title: "Bob Ross", isDirect: true, heroes: [bob])
        #expect(choice == .initials(ChatListInitials(text: "BR", paletteIndex: AvatarColorHash.paletteIndex(forId: bob.userId))))
    }

    @Test
    func directChatWithoutHeroesTakesTwoInitialsFromTheTitleColoredByRoom() {
        let choice = choose(roomId: "!dm:example.org", title: "Dana Scully", isDirect: true, heroes: [])
        #expect(choice == .initials(ChatListInitials(text: "DS", paletteIndex: AvatarColorHash.paletteIndex(forId: "!dm:example.org"))))
    }

    @Test
    func directChatNeverClusters() {
        let choice = choose(roomId: "!dm:example.org", title: "Bob, Carol", isDirect: true, heroes: [bob, carol])
        guard case .initials = choice else {
            Issue.record("expected initials, got \(choice)")
            return
        }
    }

    @Test
    func groupWithTwoOrMoreHeroesClusters() {
        let choice = choose(roomId: "!g:example.org", title: "Bob, Carol", isDirect: false, heroes: [bob, carol])
        #expect(choice == .cluster(heroes: [bob, carol]))
    }

    @Test
    func groupWithOneHeroTakesTheRoomInitial() {
        let choice = choose(roomId: "!g:example.org", title: "Book club", isDirect: false, heroes: [bob])
        #expect(choice == .initials(.room(title: "Book club", roomId: "!g:example.org")))
        #expect(choice == .initials(ChatListInitials(text: "B", paletteIndex: AvatarColorHash.paletteIndex(forId: "!g:example.org"))))
    }

    @Test
    func emptyAvatarUrlCountsAsNone() {
        let choice = ChatListAvatarChoice.choose(roomId: "!g:example.org", title: "Book club", avatarUrl: "", isDirect: false, heroes: [])
        #expect(choice == .initials(.room(title: "Book club", roomId: "!g:example.org")))
    }

    @Test
    func rowModelUsesTheSameRule() {
        let model = ChatListRowModel(id: "!g:example.org", title: "Group", heroes: [bob, carol], otherMemberCount: 2)
        #expect(model.avatarChoice == .cluster(heroes: [bob, carol]))
    }

    // MARK: Hero filter

    @Test
    func filterDropsServiceMembersAndBridgeBotsAndKeepsServerOrder() {
        let heroes = [
            ChatListHero(userId: "@whatsapp_1:example.org"),
            ChatListHero(userId: "@whatsappbot:example.org"),
            ChatListHero(userId: "@audit:example.org"),
            ChatListHero(userId: "@whatsapp_2:example.org"),
            ChatListHero(userId: "@SignalBot:example.org"),
        ]
        let visible = ChatListHero.visible(heroes, serviceMembers: ["@audit:example.org"])
        #expect(visible.map(\.userId) == ["@whatsapp_1:example.org", "@whatsapp_2:example.org"])
    }

    @Test
    func bridgeBotNamesCoverEveryNetwork() {
        let expected: Set = [
            "slackbot", "whatsappbot", "signalbot", "discordbot", "telegrambot", "googlechatbot", "groupmebot",
            "metabot", "instagrambot", "facebookbot", "gmessagesbot", "linkedinbot", "twitterbot",
        ]
        #expect(ChatListHero.bridgeBotLocalparts == expected)
    }

    @Test
    func aPuppetIsNotABot() {
        #expect(!ChatListHero.isBridgeBot(userId: "@whatsapp_15551234567:example.org"))
        #expect(!ChatListHero.isBridgeBot(userId: "@bob:example.org"))
        #expect(ChatListHero.isBridgeBot(userId: "@telegrambot:beeper.local"))
    }

    // MARK: Member count

    @Test
    func otherMemberCountExcludesTheUserAndFloorsAtZero() {
        #expect(ChatListRowModel.countOtherMembers(joinedMembersCount: 0) == 0)
        #expect(ChatListRowModel.countOtherMembers(joinedMembersCount: 1) == 0)
        #expect(ChatListRowModel.countOtherMembers(joinedMembersCount: 7) == 6)
        #expect(ChatListRowModel.countOtherMembers(joinedMembersCount: UInt64.max) == Int.max)
    }

    // MARK: Cluster layout

    @Test
    func compactModeShowsUpToThreeFacesAndNoLabel() {
        let cluster = ChatListAvatarCluster(heroes: fiveHeroes, otherMemberCount: 40, mode: .compact)
        #expect(cluster.faces == [alice, bob, carol])
        #expect(cluster.overflowText == nil)
    }

    @Test
    func fullModeShowsFiveFacesWhenEveryoneFits() {
        let cluster = ChatListAvatarCluster(heroes: fiveHeroes, otherMemberCount: 5, mode: .full)
        #expect(cluster.faces == fiveHeroes)
        #expect(cluster.overflowText == nil)
    }

    @Test
    func fullModeOverflowShowsFourFacesAndPlusN() {
        let cluster = ChatListAvatarCluster(heroes: fiveHeroes, otherMemberCount: 12, mode: .full)
        #expect(cluster.faces == [alice, bob, carol, dan])
        #expect(cluster.overflowText == "+8")
    }

    @Test
    func overflowCountsMembersWithoutAFace() {
        // Bridge bots were filtered, so only three heroes are left.
        let cluster = ChatListAvatarCluster(heroes: [alice, bob, carol], otherMemberCount: 9, mode: .full)
        #expect(cluster.faces == [alice, bob, carol])
        #expect(cluster.overflowText == "+6")
    }

    @Test
    func smallGroupHasNoLabel() {
        let cluster = ChatListAvatarCluster(heroes: [alice, bob], otherMemberCount: 2, mode: .full)
        #expect(cluster.faces == [alice, bob])
        #expect(cluster.overflowText == nil)
    }

    @Test
    func overflowTextCapsAt99() {
        #expect(ChatListAvatarCluster.overflowText(hiddenCount: 1) == "+1")
        #expect(ChatListAvatarCluster.overflowText(hiddenCount: 99) == "+99")
        #expect(ChatListAvatarCluster.overflowText(hiddenCount: 100) == "99+")
        #expect(ChatListAvatarCluster(heroes: fiveHeroes, otherMemberCount: 500, mode: .full).overflowText == "99+")
    }

    // MARK: Initials

    @Test(arguments: [
        ("Seth Redacted (WhatsApp)", "SR"),
        ("alice", "A"),
        ("  bob   ross  ", "BR"),
        ("(Bob) Smith", "BS"),
        ("🎉 Party Planner", "PP"),
        ("Émile Zola", "ÉZ"),
        ("José María Álvarez", "JM"),
        ("Дмитрий Иванов", "ДИ"),
    ])
    func personInitialsTakeTheFirstLetterOfTwoWords(displayName: String, expected: String) {
        #expect(ChatListInitials.personText(displayName: displayName, userId: "@x:example.org") == expected)
    }

    @Test
    func personInitialsFallBackToTheLocalpartThenHash() {
        #expect(ChatListInitials.personText(displayName: nil, userId: "@bob:example.org") == "B")
        #expect(ChatListInitials.personText(displayName: "", userId: "@_carol:example.org") == "C")
        #expect(ChatListInitials.personText(displayName: "🎉 42", userId: "@dan:example.org") == "D")
        #expect(ChatListInitials.personText(displayName: nil, userId: "@123:example.org") == "#")
    }

    @Test
    func roomInitialKeepsTheOneCharacterRule() {
        #expect(ChatListInitials.roomText(title: "book club") == "B")
        #expect(ChatListInitials.roomText(title: "#omaha-board-games") == "O")
        #expect(ChatListInitials.roomText(title: "2026 trip") == "2")
        #expect(ChatListInitials.roomText(title: "🎉") == "#")
    }

    // MARK: Palette hash

    @Test
    func fnv1aMatchesTheReferenceVectors() {
        // Test vectors from the FNV reference (draft-eastlake-fnv).
        #expect(AvatarColorHash.fnv1a32("") == 0x811C_9DC5)
        #expect(AvatarColorHash.fnv1a32("a") == 0xE40C_292C)
        #expect(AvatarColorHash.fnv1a32("foobar") == 0xBF9C_F968)
    }

    @Test
    func knownIdsMapToFixedSlots() {
        #expect(AvatarColorHash.paletteSize == 16)
        // 0xF7D6FFC5 % 16 == 5
        #expect(AvatarColorHash.paletteIndex(forId: "@alice:example.org") == 5)
        // 0x9B1E88EA % 16 == 10
        #expect(AvatarColorHash.paletteIndex(forId: "@bob:example.org") == 10)
        // 0x6D98BBDF % 16 == 15
        #expect(AvatarColorHash.paletteIndex(forId: "!room:example.org") == 15)
        #expect(ChatListInitials.person(displayName: "Alice", userId: "@alice:example.org").paletteIndex == 5)
    }

    @Test
    func paletteIndexIsAlwaysInRange() {
        let ids = ["", "a", "@ada:example.org", "!x:davlin.io", "😀", String(repeating: "z", count: 500)]
        for id in ids {
            #expect((0 ..< AvatarColorHash.paletteSize).contains(AvatarColorHash.paletteIndex(forId: id)))
        }
    }
}

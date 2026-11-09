@testable import Models
import Testing

/// MATRIX-133: the member fallback for the bubble cluster (member filters and
/// order, the fallback decision, and the merge with the room's heroes).
struct ChatListMemberClusterTests {
    private let me = "@me:example.org"

    private func member(
        _ localpart: String,
        name: String? = nil,
        joined: Bool = true,
        ignored: Bool = false,
        power: ChatListMember.PowerLevel = .value(0)
    ) -> ChatListMember {
        ChatListMember(
            userId: "@\(localpart):example.org",
            displayName: name,
            isJoined: joined,
            isIgnored: ignored,
            powerLevel: power
        )
    }

    private func ids(_ heroes: [ChatListHero]) -> [String] {
        heroes.map(\.userId)
    }

    // MARK: Filters

    @Test
    func keepsJoinedMembersOnly() {
        let heroes = ChatListMemberCluster.heroes(
            from: [member("alice", name: "Alice"), member("bob", name: "Bob", joined: false)],
            ownUserId: me,
            serviceMembers: []
        )
        #expect(ids(heroes) == ["@alice:example.org"])
    }

    @Test
    func dropsIgnoredMembersAndTheUser() {
        let heroes = ChatListMemberCluster.heroes(
            from: [
                ChatListMember(userId: me, displayName: "Me", powerLevel: .value(100)),
                member("alice", name: "Alice"),
                member("troll", name: "Troll", ignored: true),
            ],
            ownUserId: me,
            serviceMembers: []
        )
        #expect(ids(heroes) == ["@alice:example.org"])
    }

    @Test
    func dropsServiceMembersAndBridgeBots() {
        let heroes = ChatListMemberCluster.heroes(
            from: [
                member("whatsappbot", name: "WhatsApp bridge bot", power: .value(100)),
                member("service", name: "Service"),
                member("whatsapp_123", name: "Alice"),
            ],
            ownUserId: me,
            serviceMembers: ["@service:example.org"]
        )
        #expect(ids(heroes) == ["@whatsapp_123:example.org"])
    }

    // MARK: Order

    @Test
    func sortsByPowerLevelFirstWithInfiniteOnTop() {
        let heroes = ChatListMemberCluster.heroes(
            from: [
                member("user", name: "Aaron"),
                member("mod", name: "Zed", power: .value(50)),
                member("creator", name: "Yan", power: .infinite),
                member("admin", name: "Xia", power: .value(100)),
            ],
            ownUserId: me,
            serviceMembers: []
        )
        #expect(ids(heroes) == [
            "@creator:example.org",
            "@admin:example.org",
            "@mod:example.org",
            "@user:example.org",
        ])
    }

    @Test
    func infiniteRanksAboveTheLargestValue() {
        #expect(ChatListMember.PowerLevel.infinite > .value(Int64.max))
        #expect(ChatListMember.PowerLevel.value(100) > .value(50))
        #expect(ChatListMember.PowerLevel.value(-1) < .value(0))
    }

    @Test
    func sortsByDisplayNameIgnoringCaseThenByUserId() {
        let heroes = ChatListMemberCluster.heroes(
            from: [
                member("carol", name: "carol"),
                member("bob2", name: "Bob"),
                member("alice", name: "Alice"),
                member("bob1", name: "bob"),
            ],
            ownUserId: me,
            serviceMembers: []
        )
        #expect(ids(heroes) == [
            "@alice:example.org",
            "@bob1:example.org",
            "@bob2:example.org",
            "@carol:example.org",
        ])
    }

    @Test
    func memberWithoutDisplayNameSortsByUserId() {
        let heroes = ChatListMemberCluster.heroes(
            from: [member("zoe", name: "Zoe"), member("bart"), member("amy", name: "Amy")],
            ownUserId: me,
            serviceMembers: []
        )
        // "@bart:example.org" sorts before letters: "@" is below "A".
        #expect(ids(heroes) == ["@bart:example.org", "@amy:example.org", "@zoe:example.org"])
    }

    @Test
    func keepsAtMostFiveHeroes() {
        let members = (1 ... 8).map { (index: Int) -> ChatListMember in
            member("user\(index)", name: "User \(index)")
        }
        let heroes = ChatListMemberCluster.heroes(from: members, ownUserId: me, serviceMembers: [])
        #expect(heroes.count == 5)
        #expect(ids(heroes) == (1 ... 5).map { "@user\($0):example.org" })
    }

    @Test
    func heroesCarryNameAndAvatar() {
        let alice = ChatListMember(userId: "@alice:example.org", displayName: "Alice", avatarUrl: "mxc://example.org/a")
        let heroes = ChatListMemberCluster.heroes(from: [alice], ownUserId: me, serviceMembers: [])
        #expect(heroes == [ChatListHero(userId: "@alice:example.org", displayName: "Alice", avatarUrl: "mxc://example.org/a")])
    }

    // MARK: Cluster value

    @Test
    func countsEveryFilteredOtherMember() {
        let members = [ChatListMember(userId: me)]
            + (1 ... 8).map { (index: Int) -> ChatListMember in member("user\(index)") }
            + [member("signalbot"), member("gone", joined: false)]
        let cluster = ChatListMemberCluster(members: members, ownUserId: me, serviceMembers: [], source: .fetchedMembers)
        #expect(cluster.otherMemberCount == 8)
        #expect(cluster.heroes.count == 5)
        #expect(cluster.source == .fetchedMembers)
        #expect(cluster.drawsCluster)
    }

    @Test
    func detectsTheNetworkFromMemberIds() {
        let cluster = ChatListMemberCluster(
            members: [member("whatsappbot"), member("whatsapp_15551234"), ChatListMember(userId: me)],
            ownUserId: me,
            serviceMembers: [],
            source: .localMembers
        )
        #expect(cluster.network == .whatsApp)
        #expect(!cluster.drawsCluster)
    }

    // MARK: Fallback decision

    @Test
    func groupWithoutAvatarAndFewHeroesNeedsMembers() {
        #expect(ChatListMemberCluster.needsMembers(isDirect: false, avatarUrl: nil, visibleHeroCount: 0))
        #expect(ChatListMemberCluster.needsMembers(isDirect: false, avatarUrl: "", visibleHeroCount: 1))
    }

    @Test
    func enoughHeroesOrAvatarOrDirectNeedsNoMembers() {
        #expect(!ChatListMemberCluster.needsMembers(isDirect: false, avatarUrl: nil, visibleHeroCount: 2))
        #expect(!ChatListMemberCluster.needsMembers(isDirect: false, avatarUrl: "mxc://example.org/r", visibleHeroCount: 0))
        #expect(!ChatListMemberCluster.needsMembers(isDirect: true, avatarUrl: nil, visibleHeroCount: 0))
    }

    // MARK: Merge with heroes

    private let alice = ChatListHero(userId: "@alice:example.org", displayName: "Alice")
    private let bob = ChatListHero(userId: "@bob:example.org", displayName: "Bob")
    private let carol = ChatListHero(userId: "@carol:example.org", displayName: "Carol")

    @Test
    func withoutMembersRowKeepsHeroesAndJoinedCount() {
        let people = ChatListRowPeople(
            visibleHeroes: [alice],
            heroUserIds: ["@alice:example.org"],
            joinedMembersCount: 4,
            members: nil
        )
        #expect(people == ChatListRowPeople(heroes: [alice], otherMemberCount: 3, network: nil))
    }

    @Test
    func withoutRoomInfoCountIsZero() {
        let people = ChatListRowPeople(visibleHeroes: [], heroUserIds: [], joinedMembersCount: nil, members: nil)
        #expect(people.otherMemberCount == 0)
    }

    @Test
    func loadedMembersReplaceTooFewHeroes() {
        let members = ChatListMemberCluster(source: .fetchedMembers, heroes: [bob, carol], otherMemberCount: 7, network: .signal)
        let people = ChatListRowPeople(
            visibleHeroes: [alice],
            heroUserIds: ["@alice:example.org"],
            joinedMembersCount: 12,
            members: members
        )
        #expect(people == ChatListRowPeople(heroes: [bob, carol], otherMemberCount: 7, network: .signal))
    }

    @Test
    func twoVisibleHeroesWinOverMembers() {
        let members = ChatListMemberCluster(source: .localMembers, heroes: [carol, alice, bob], otherMemberCount: 3, network: nil)
        let people = ChatListRowPeople(
            visibleHeroes: [alice, bob],
            heroUserIds: ["@alice:example.org", "@bob:example.org"],
            joinedMembersCount: 4,
            members: members
        )
        #expect(people.heroes == [alice, bob])
        #expect(people.otherMemberCount == 3)
    }

    @Test
    func membersWithNoMoreFacesKeepTheHeroes() {
        let members = ChatListMemberCluster(source: .localMembers, heroes: [bob], otherMemberCount: 1, network: nil)
        let people = ChatListRowPeople(
            visibleHeroes: [alice],
            heroUserIds: ["@alice:example.org"],
            joinedMembersCount: 2,
            members: members
        )
        #expect(people.heroes == [alice])
    }

    @Test
    func heroNetworkWinsOverMemberNetwork() {
        let members = ChatListMemberCluster(source: .localMembers, heroes: [], otherMemberCount: 0, network: .signal)
        let people = ChatListRowPeople(
            visibleHeroes: [],
            heroUserIds: ["@telegram_1:example.org"],
            joinedMembersCount: 2,
            members: members
        )
        #expect(people.network == .telegram)
    }

    @Test
    func memberNetworkFillsMissingHeroNetwork() {
        let members = ChatListMemberCluster(source: .fetchedMembers, heroes: [], otherMemberCount: 0, network: .discord)
        let people = ChatListRowPeople(visibleHeroes: [], heroUserIds: [], joinedMembersCount: 2, members: members)
        #expect(people.network == .discord)
    }
}

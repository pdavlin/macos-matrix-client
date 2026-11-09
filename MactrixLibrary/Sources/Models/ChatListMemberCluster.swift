import Foundation

/// One room member, as the chat-list member fallback reads it (MATRIX-133).
///
/// The Core layer copies each SDK `RoomMember` into this value, so the hero
/// rules and their tests need no SDK type.
public struct ChatListMember: Equatable, Sendable {
    /// A member's power level. `.infinite` (a room creator in room version
    /// 12) ranks above every `.value`.
    public enum PowerLevel: Comparable, Sendable {
        // The case order is the sort order: synthesized `Comparable` puts
        // every `.value` below `.infinite`, and compares values numerically.
        case value(Int64)
        case infinite
    }

    /// The full Matrix user ID, for example `@alice:example.org`.
    public var userId: String
    /// The member's display name, when the server knows one.
    public var displayName: String?
    /// The `mxc://` URL of the member's avatar, when they set one.
    public var avatarUrl: String?
    /// The membership is `join`. Invited, left, banned, and knocking members
    /// are not in the chat.
    public var isJoined: Bool
    /// The user ignores this member.
    public var isIgnored: Bool
    public var powerLevel: PowerLevel

    public init(
        userId: String,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        isJoined: Bool = true,
        isIgnored: Bool = false,
        powerLevel: PowerLevel = .value(0)
    ) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.isJoined = isJoined
        self.isIgnored = isIgnored
        self.powerLevel = powerLevel
    }
}

/// Where a group row's bubble cluster gets its faces (MATRIX-133).
///
/// The raw values are the words the sidebar diagnostic log writes.
public enum ChatListClusterSource: String, Sendable {
    /// The room's own heroes (`RoomInfo.heroes`).
    case heroes
    /// The members in the local store (`membersNoSync()`).
    case localMembers = "local-members"
    /// The members from the homeserver (`members()`).
    case fetchedMembers = "fetched-members"
    /// No source gave enough faces: the row draws the room's initial.
    case none
}

/// A group's bubble-cluster faces, built from its loaded members (MATRIX-133).
///
/// The server sends heroes only for a room without a name of its own, and a
/// mautrix bridge names every group, so most bridged groups have no heroes.
/// When a group has no room avatar and too few visible heroes, `SidebarRoom`
/// loads the room's members and keeps one of these values. The row then
/// takes its faces, "+N" count, and network badge from it.
public struct ChatListMemberCluster: Equatable, Sendable {
    /// The most faces the fallback keeps: the full cluster's capacity
    /// (`ChatListAvatarCluster.Mode.full`).
    public static let maximumHeroes = ChatListAvatarCluster.Mode.full.capacity

    /// The member load this value came from: `.localMembers` or
    /// `.fetchedMembers`.
    public var source: ChatListClusterSource
    /// Up to `maximumHeroes` faces, in `heroes(from:ownUserId:serviceMembers:)`
    /// order.
    public var heroes: [ChatListHero]
    /// Joined members other than the user, after every filter of
    /// `heroes(from:ownUserId:serviceMembers:)`. The "+N" label counts these.
    public var otherMemberCount: Int
    /// The network of the first filtered member with a known puppet prefix.
    public var network: ChatListNetwork?

    public init(source: ChatListClusterSource, heroes: [ChatListHero], otherMemberCount: Int, network: ChatListNetwork?) {
        self.source = source
        self.heroes = heroes
        self.otherMemberCount = otherMemberCount
        self.network = network
    }

    /// True when the members give enough faces for a cluster
    /// (`ChatListAvatarChoice.clusterMinimumHeroes`).
    public var drawsCluster: Bool {
        heroes.count >= ChatListAvatarChoice.clusterMinimumHeroes
    }

    /// Builds the cluster from a member list.
    ///
    /// - Parameters:
    ///   - members: the room's members, in any order.
    ///   - ownUserId: the user's own Matrix user ID. The user is never a face.
    ///   - serviceMembers: the room's service members (`RoomInfo.serviceMembers`).
    ///   - source: the member load the list came from.
    public init(
        members: [ChatListMember],
        ownUserId: String,
        serviceMembers: some Sequence<String>,
        source: ChatListClusterSource
    ) {
        let others = Self.otherMembers(members, ownUserId: ownUserId, serviceMembers: serviceMembers)
        self.init(
            source: source,
            heroes: Array(others.prefix(Self.maximumHeroes)),
            otherMemberCount: others.count,
            network: ChatListNetwork.detect(heroUserIds: others.lazy.map(\.userId))
        )
    }

    /// The cluster faces for a member list: up to `maximumHeroes` heroes.
    ///
    /// See `otherMembers(_:ownUserId:serviceMembers:)` for the filters and the
    /// order.
    ///
    /// ```swift
    /// ChatListMemberCluster.heroes(
    ///     from: [
    ///         ChatListMember(userId: "@me:example.org"),
    ///         ChatListMember(userId: "@whatsappbot:example.org", powerLevel: .value(100)),
    ///         ChatListMember(userId: "@bob:example.org", displayName: "Bob"),
    ///         ChatListMember(userId: "@alice:example.org", displayName: "alice"),
    ///     ],
    ///     ownUserId: "@me:example.org",
    ///     serviceMembers: []
    /// ) // [@alice:example.org, @bob:example.org]
    /// ```
    public static func heroes(
        from members: [ChatListMember],
        ownUserId: String,
        serviceMembers: some Sequence<String>
    ) -> [ChatListHero] {
        Array(otherMembers(members, ownUserId: ownUserId, serviceMembers: serviceMembers).prefix(maximumHeroes))
    }

    /// Every member that may be a face, in face order.
    ///
    /// Keeps joined members only, drops ignored members and the user, then
    /// applies `ChatListHero.visible` (service members and bridge bots). The
    /// order is the highest power level first (`.infinite` above any value),
    /// then the display name ignoring case (a member without one sorts by
    /// user ID), then the user ID. The order is stable for one member list,
    /// so the cluster does not shuffle between loads.
    static func otherMembers(
        _ members: [ChatListMember],
        ownUserId: String,
        serviceMembers: some Sequence<String>
    ) -> [ChatListHero] {
        let candidates = members.filter { (member: ChatListMember) -> Bool in
            member.isJoined && !member.isIgnored && member.userId != ownUserId
        }
        let sorted = candidates.sorted { (lhs: ChatListMember, rhs: ChatListMember) -> Bool in
            if lhs.powerLevel != rhs.powerLevel {
                return lhs.powerLevel > rhs.powerLevel
            }
            let nameOrder = sortName(lhs).caseInsensitiveCompare(sortName(rhs))
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.userId < rhs.userId
        }
        let heroes = sorted.map { (member: ChatListMember) -> ChatListHero in
            ChatListHero(userId: member.userId, displayName: member.displayName, avatarUrl: member.avatarUrl)
        }
        return ChatListHero.visible(heroes, serviceMembers: serviceMembers)
    }

    /// The name a member sorts by: the display name, or the user ID when the
    /// member has no display name.
    private static func sortName(_ member: ChatListMember) -> String {
        if let displayName = member.displayName, !displayName.isEmpty {
            return displayName
        }
        return member.userId
    }

    /// True when a row needs the member fallback: a group (not direct) with
    /// no room avatar and fewer than `ChatListAvatarChoice.clusterMinimumHeroes`
    /// visible heroes.
    ///
    /// - Parameters:
    ///   - isDirect: the SDK's direct-chat flag.
    ///   - avatarUrl: the room's own avatar URL.
    ///   - visibleHeroCount: the count of `ChatListHero.visible` heroes.
    public static func needsMembers(isDirect: Bool, avatarUrl: String?, visibleHeroCount: Int) -> Bool {
        isClusterCandidate(isDirect: isDirect, avatarUrl: avatarUrl)
            && visibleHeroCount < ChatListAvatarChoice.clusterMinimumHeroes
    }

    /// True for a group (not direct) with no room avatar: the rows that can
    /// draw a cluster, and the rows the diagnostic log reports.
    public static func isClusterCandidate(isDirect: Bool, avatarUrl: String?) -> Bool {
        !isDirect && (avatarUrl ?? "").isEmpty
    }
}

/// The people a chat-list row shows: faces, "+N" count, and network badge
/// (MATRIX-133).
public struct ChatListRowPeople: Equatable, Sendable {
    public var heroes: [ChatListHero]
    public var otherMemberCount: Int
    public var network: ChatListNetwork?

    public init(heroes: [ChatListHero], otherMemberCount: Int, network: ChatListNetwork?) {
        self.heroes = heroes
        self.otherMemberCount = otherMemberCount
        self.network = network
    }

    /// Merges the room's heroes with the loaded members.
    ///
    /// - The faces are the visible heroes when there are at least
    ///   `ChatListAvatarChoice.clusterMinimumHeroes` of them. Otherwise they
    ///   are the members' faces, when the members give more faces than the
    ///   heroes.
    /// - The count is the members' filtered count when members are loaded,
    ///   else the SDK's joined count minus the user.
    /// - The network is the heroes' network, else the members' network.
    ///
    /// - Parameters:
    ///   - visibleHeroes: the room's visible heroes (`ChatListHero.visible`).
    ///   - heroUserIds: every hero's user ID, before the visible filter. The
    ///     network detector reads these.
    ///   - joinedMembersCount: the SDK's `RoomInfo.joinedMembersCount`, or nil
    ///     when room info has not loaded.
    ///   - members: the loaded member cluster, or nil when none loaded.
    public init(
        visibleHeroes: [ChatListHero],
        heroUserIds: [String],
        joinedMembersCount: UInt64?,
        members: ChatListMemberCluster?
    ) {
        let heroesSuffice = visibleHeroes.count >= ChatListAvatarChoice.clusterMinimumHeroes
        if !heroesSuffice, let members, members.heroes.count > visibleHeroes.count {
            heroes = members.heroes
        } else {
            heroes = visibleHeroes
        }
        if let members {
            otherMemberCount = members.otherMemberCount
        } else {
            otherMemberCount = joinedMembersCount.map(ChatListRowModel.countOtherMembers(joinedMembersCount:)) ?? 0
        }
        network = ChatListNetwork.detect(heroUserIds: heroUserIds) ?? members?.network
    }
}

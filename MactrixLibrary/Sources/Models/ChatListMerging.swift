import Foundation

/// One room of the chat list, as the merged-chat pass reads it (MATRIX-141).
///
/// The row model already holds the display values the merged row reuses:
/// the title, the unread state, the composed preview and timestamp text, the
/// network badge, and the avatar inputs. This type adds the two values the
/// row does not keep: the sort time as a date and the favourite flag.
public struct ChatListEntry: Equatable, Sendable, Identifiable {
    /// The room's chat-list row (`SidebarRoom.chatListRow`).
    public var row: ChatListRowModel
    /// The time of the room's latest event, or nil when the room has none.
    /// It picks the newest member of a merged chat.
    public var lastActivity: Date?
    /// The room is a favourite, so it shows in the pinned grid.
    public var isFavourite: Bool

    public var id: String {
        row.id
    }

    public init(row: ChatListRowModel, lastActivity: Date? = nil, isFavourite: Bool = false) {
        self.row = row
        self.lastActivity = lastActivity
        self.isFavourite = isFavourite
    }
}

/// One merged chat as the chat list shows it (MATRIX-141).
///
/// Built only by `ChatListMerging`. It holds the members that are in the
/// chat list now; `merge` still names every member, present or not.
public struct MergedChatListEntry: Equatable, Sendable, Identifiable {
    /// The merged chat from the document.
    public var merge: MergedChat
    /// The row `ChatListRow` and `PinnedChatTile` draw. Its `id` is the
    /// merged chat's `id`, not a room ID.
    public var row: ChatListRowModel
    /// The member rooms the chat list holds, in the merged chat's order.
    /// Never empty.
    public var memberRoomIds: [String]
    /// The present member with the newest activity. The row shows its
    /// preview and timestamp.
    public var newestRoomId: String
    /// The present member whose avatar the row shows.
    public var avatarRoomId: String
    /// The distinct networks of the present members, in the merged chat's
    /// order. The row draws a badge for each, up to
    /// `ChatListRowModel.badgeNetworkLimit`.
    public var networks: [ChatListNetwork]
    /// The newest member's activity time.
    public var lastActivity: Date?
    /// Any present member is a favourite.
    public var isFavourite: Bool

    public var id: String {
        merge.id
    }
}

/// One row of the chat list after merging: a plain room or a merged chat
/// (MATRIX-141).
public enum ChatListItem: Equatable, Sendable, Identifiable {
    case room(ChatListEntry)
    case merged(MergedChatListEntry)

    /// The room ID, or the merged chat's ID. A merged chat ID is a UUID, so
    /// it never equals a room ID (room IDs start with "!").
    public var id: String {
        switch self {
        case let .room(entry): entry.id
        case let .merged(merged): merged.id
        }
    }

    /// The row to draw.
    public var row: ChatListRowModel {
        switch self {
        case let .room(entry): entry.row
        case let .merged(merged): merged.row
        }
    }

    /// The item shows in the pinned grid.
    public var isFavourite: Bool {
        switch self {
        case let .room(entry): entry.isFavourite
        case let .merged(merged): merged.isFavourite
        }
    }

    /// The newest activity time of the item.
    public var lastActivity: Date? {
        switch self {
        case let .room(entry): entry.lastActivity
        case let .merged(merged): merged.lastActivity
        }
    }

    /// Every room the item stands for: one room, or the present members of
    /// a merged chat. A per-room action (mute, mark read) applies to each.
    public var roomIds: [String] {
        switch self {
        case let .room(entry): [entry.id]
        case let .merged(merged): merged.memberRoomIds
        }
    }

    /// The merged chat, when the item is one.
    public var mergedChat: MergedChatListEntry? {
        if case let .merged(merged) = self {
            return merged
        }
        return nil
    }
}

/// Folds merged chats into the chat list (MATRIX-141, contract §4 M2.5).
///
/// Presentation only: the SDK still sorts and filters the rooms, and this
/// pass replaces the member rows of each merged chat with one merged row.
///
/// Rules:
/// - Member rows leave the list. A merged chat shows when at least one of its
///   members is in the list (the filter or a left room can drop the others),
///   and it then sums only the members that are present.
/// - The merged row takes the place of its newest member, so the list keeps
///   the SDK's recency order. The newest member is the one with the latest
///   `lastActivity`; a nil time is the oldest, and a tie goes to the member
///   the SDK put first.
/// - Unread: the counts add up, a mention or an unread flag on any member
///   counts. The row is muted only when every present member is muted, and
///   "muted by label" only when every present member is muted by a label
///   (orchestrator decision 2026-11-10: the document has no mute of its own).
/// - Preview, timestamp, and sort time come from the newest member. A send
///   failure on any member shows the red dot, because the failed message
///   needs the user whichever member holds it.
/// - Avatar: the `avatarRoom` member when present, else the first present
///   member (in the merged chat's order) with an avatar image, else the first
///   present member. The title is the merged chat's name, or the avatar
///   member's title when the name is blank.
/// - Favourite: the merged chat is pinned when any present member is a
///   favourite, so one merged chat never shows twice (once in the grid and
///   once in the list).
/// - A room in two merged chats belongs to the first one in the document.
public enum ChatListMerging {
    /// The chat list with merged chats folded in.
    ///
    /// - Parameters:
    ///   - entries: the rooms the sidebar shows, favourites included, in SDK
    ///     (recency) order. Hidden-label rooms are already removed.
    ///   - document: the account's merged chats.
    /// - Returns: one item per plain room and one per merged chat with a
    ///   present member, in display order.
    ///
    /// ```swift
    /// let items = ChatListMerging.items(entries: entries, document: document)
    /// // [.room(!a), .merged(Seth), .room(!d)]
    /// ```
    public static func items(entries: [ChatListEntry], document: MergedChatDocument) -> [ChatListItem] {
        let owner = mergeOwners(document)
        guard !owner.isEmpty else {
            return entries.map(ChatListItem.room)
        }

        var groups: [Int: [ChatListEntry]] = [:]
        for entry in entries {
            guard let mergeIndex = owner[entry.id] else { continue }
            if groups[mergeIndex, default: []].contains(where: { $0.id == entry.id }) {
                continue
            }
            groups[mergeIndex, default: []].append(entry)
        }

        var newestByMerge: [Int: String] = [:]
        for (mergeIndex, members) in groups {
            if let newest = newest(of: members) {
                newestByMerge[mergeIndex] = newest.id
            }
        }

        var items: [ChatListItem] = []
        var emitted: Set<Int> = []
        for entry in entries {
            guard let mergeIndex = owner[entry.id] else {
                items.append(.room(entry))
                continue
            }
            guard newestByMerge[mergeIndex] == entry.id, !emitted.contains(mergeIndex),
                  let members = groups[mergeIndex]
            else {
                continue
            }
            emitted.insert(mergeIndex)
            let merge = document.merges[mergeIndex]
            if let merged = mergedEntry(merge: merge, members: members) {
                items.append(.merged(merged))
            }
        }
        return items
    }

    /// The chat list with merged chats folded in, split into the pinned grid
    /// and the list as `VisibleChatList.visible` splits rooms.
    ///
    /// - Parameters:
    ///   - entries: as for `items(entries:document:)`.
    ///   - document: the account's merged chats.
    public static func visible(entries: [ChatListEntry], document: MergedChatDocument) -> VisibleChatList<ChatListItem> {
        let items = items(entries: entries, document: document)
        return VisibleChatList(
            favorites: items.filter(\.isFavourite),
            list: items.filter { !$0.isFavourite }
        )
    }

    /// Builds one merged entry from its present members.
    ///
    /// - Parameters:
    ///   - merge: the merged chat.
    ///   - members: the present members this merged chat owns, in SDK
    ///     order, without duplicates.
    /// - Returns: nil when no member is present.
    static func mergedEntry(merge: MergedChat, members: [ChatListEntry]) -> MergedChatListEntry? {
        guard let newest = newest(of: members) else { return nil }
        let byId = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var memberOrder: [String] = []
        for roomId in merge.rooms where byId[roomId] != nil && !memberOrder.contains(roomId) {
            memberOrder.append(roomId)
        }
        let ordered = memberOrder.compactMap { byId[$0] }
        guard let avatarMember = avatarMember(merge: merge, ordered: ordered) else { return nil }

        var networks: [ChatListNetwork] = []
        for network in ordered.compactMap(\.row.network) where !networks.contains(network) {
            networks.append(network)
        }

        let trimmedName = merge.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var row = ChatListRowModel(
            id: merge.id,
            title: trimmedName.isEmpty ? avatarMember.row.title : trimmedName,
            avatarUrl: avatarMember.row.avatarUrl,
            isDirect: avatarMember.row.isDirect,
            preview: newest.row.preview,
            timestamp: newest.row.timestamp,
            unread: unread(of: ordered.map(\.row.unread)),
            hasSendFailure: ordered.contains { $0.row.hasSendFailure },
            network: networks.first,
            heroes: avatarMember.row.heroes,
            otherMemberCount: avatarMember.row.otherMemberCount
        )
        row.additionalNetworks = Array(networks.dropFirst())

        return MergedChatListEntry(
            merge: merge,
            row: row,
            memberRoomIds: memberOrder,
            newestRoomId: newest.id,
            avatarRoomId: avatarMember.id,
            networks: networks,
            lastActivity: newest.lastActivity,
            isFavourite: ordered.contains(where: \.isFavourite)
        )
    }

    /// The unread state of a merged row from its members' states.
    ///
    /// The counts add up (saturating at `UInt64.max`). A mention or an
    /// unread flag on any member counts. Muted needs every member muted;
    /// muted by label needs every member muted by a label. No members gives
    /// the read, unmuted state.
    public static func unread(of members: [ChatListUnread]) -> ChatListUnread {
        guard !members.isEmpty else { return ChatListUnread() }
        let count = members.reduce(UInt64(0)) { total, unread in
            let (sum, overflow) = total.addingReportingOverflow(unread.count)
            return overflow ? UInt64.max : sum
        }
        return ChatListUnread(
            count: count,
            hasMention: members.contains(where: \.hasMention),
            isUnread: members.contains(where: \.isUnread),
            isMuted: members.allSatisfy(\.isMuted),
            isMutedByLabel: members.allSatisfy(\.isMutedByLabel)
        )
    }

    /// The member with the latest activity. A nil time is the oldest; a tie
    /// goes to the earlier member.
    static func newest(of members: [ChatListEntry]) -> ChatListEntry? {
        var best: ChatListEntry?
        for member in members {
            guard let current = best else {
                best = member
                continue
            }
            if (member.lastActivity ?? .distantPast) > (current.lastActivity ?? .distantPast) {
                best = member
            }
        }
        return best
    }

    /// The member whose avatar the merged row shows. See the type's rules.
    static func avatarMember(merge: MergedChat, ordered: [ChatListEntry]) -> ChatListEntry? {
        if let avatarRoom = merge.avatarRoom, let chosen = ordered.first(where: { $0.id == avatarRoom }) {
            return chosen
        }
        return ordered.first(where: \.row.hasAvatarImage) ?? ordered.first
    }

    /// Room ID to the index of the first merged chat that holds it.
    static func mergeOwners(_ document: MergedChatDocument) -> [String: Int] {
        var owner: [String: Int] = [:]
        for (index, merge) in document.merges.enumerated() {
            for roomId in merge.rooms where owner[roomId] == nil {
                owner[roomId] = index
            }
        }
        return owner
    }
}

public extension ChatListRowModel {
    /// The most network badges a row draws (MATRIX-141).
    static let badgeNetworkLimit = 3

    /// The avatar draws an image, not initials or a cluster (MATRIX-141).
    var hasAvatarImage: Bool {
        if case .image = avatarChoice {
            return true
        }
        return false
    }

    /// The networks the avatar badges show: `network`, then
    /// `additionalNetworks`, without repeats, at most `badgeNetworkLimit`.
    var badgeNetworks: [ChatListNetwork] {
        var networks = network.map { [$0] } ?? []
        for extra in additionalNetworks where !networks.contains(extra) {
            networks.append(extra)
        }
        return Array(networks.prefix(Self.badgeNetworkLimit))
    }
}

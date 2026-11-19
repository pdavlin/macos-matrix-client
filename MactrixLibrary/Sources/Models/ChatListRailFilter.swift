import Foundation

/// What the sidebar rail selects (MATRIX-167): the Inbox, one joined space,
/// or one label (MATRIX-77). One selection per window.
///
/// This is not `ChatListFilter` (MATRIX-67, the toolbar's Inbox / Unread /
/// People choice). The two combine: the rail chooses a set of chats and the
/// chat-list filter narrows that set.
public enum ChatListRailFilter: Hashable, Sendable {
    case inbox
    /// A joined space, by room ID.
    case space(String)
    /// A label, by label ID.
    case label(String)

    /// The selected label's ID, when a label is selected.
    public var labelId: String? {
        if case let .label(id) = self {
            return id
        }
        return nil
    }

    /// The selected space's room ID, when a space is selected.
    public var spaceId: String? {
        if case let .space(id) = self {
            return id
        }
        return nil
    }

    /// The filter the window shows for this selection.
    ///
    /// A label the labels do not hold, or a space that is not on the rail,
    /// shows the Inbox. The stored selection does not change: a space that
    /// is not known yet at launch (the SDK builds its space graph late)
    /// applies when it arrives, and a space the account left shows the Inbox.
    ///
    /// - Parameters:
    ///   - labels: the labels document.
    ///   - spaceIds: the spaces the rail shows.
    public func resolved(labels: ChatLabelDocument, spaceIds: Set<String>) -> ChatListRailFilter {
        switch self {
        case .inbox:
            .inbox
        case let .space(id):
            spaceIds.contains(id) ? self : .inbox
        case let .label(id):
            labels.label(id: id) == nil ? .inbox : self
        }
    }

    /// The room IDs that narrow the SDK room list for this filter, or nil
    /// for the Inbox (no narrowing). Sorted for a space, so the value changes
    /// only when the set changes.
    ///
    /// The sidebar holds one page of the SDK list, so the narrowing has to be
    /// done by the SDK; `ChatListMerging.visible(entries:filter:labels:spaces:document:)`
    /// applies the same rule to the rows that arrive.
    ///
    /// - Parameters:
    ///   - labels: the labels document.
    ///   - spaces: the room-to-space map.
    ///   - chatIds: the account's chat rooms.
    public func narrowingRoomIds(
        labels: ChatLabelDocument,
        spaces: RoomSpaceMap,
        chatIds: some Sequence<String>
    ) -> [String]? {
        switch self {
        case .inbox:
            nil
        case let .space(id):
            spaces.rooms(in: id, among: chatIds).sorted()
        case let .label(id):
            labels.label(id: id)?.rooms
        }
    }
}

/// Which spaces hold which rooms (MATRIX-167), from the SDK's space service.
///
/// `parents` holds the direct joined parents of each room and of each
/// sub-space. A room is in a space when the space is a parent, or a parent of
/// a parent, and so on: a chat in a nested sub-space is in the top-level
/// space too.
public struct RoomSpaceMap: Equatable, Sendable {
    /// The direct joined parent spaces by child room ID. A child is a chat
    /// or a sub-space.
    public var parents: [String: [String]]

    public init(parents: [String: [String]] = [:]) {
        self.parents = parents
    }

    /// Every space that holds `roomId`, directly or through sub-spaces.
    /// A loop in the space graph ends the walk.
    public func spaceIds(of roomId: String) -> Set<String> {
        var found = Set<String>()
        var queue = parents[roomId] ?? []
        while let spaceId = queue.popLast() {
            guard spaceId != roomId, found.insert(spaceId).inserted else { continue }
            queue.append(contentsOf: parents[spaceId] ?? [])
        }
        return found
    }

    /// Whether `spaceId` holds `roomId`, directly or through sub-spaces.
    public func isRoom(_ roomId: String, in spaceId: String) -> Bool {
        spaceIds(of: roomId).contains(spaceId)
    }

    /// The rooms of `roomIds` that `spaceId` holds, in the order given.
    public func rooms(in spaceId: String, among roomIds: some Sequence<String>) -> [String] {
        roomIds.filter { isRoom($0, in: spaceId) }
    }

    /// The rooms of `roomIds` by the spaces that hold them. A room in two
    /// spaces is under both. A space with no room has no key.
    public func roomsBySpace(among roomIds: some Sequence<String>) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for roomId in roomIds {
            for spaceId in spaceIds(of: roomId) {
                result[spaceId, default: []].append(roomId)
            }
        }
        return result
    }
}

/// One space item of the sidebar rail (MATRIX-167).
public struct ChatListRailSpace: Identifiable, Equatable, Sendable {
    /// The space's room ID.
    public var id: String
    public var name: String
    /// The `mxc://` URL of the space's icon, or nil when it has none.
    public var avatarUrl: String?
    /// The unread mark, by the rule of the label items.
    public var badge: ChatLabelBadge

    public init(id: String, name: String, avatarUrl: String? = nil, badge: ChatLabelBadge = .none) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
        self.badge = badge
    }

    /// The letter a space without an icon draws: the first letter of its
    /// name, upper-cased, or nothing for a blank name.
    public var monogram: String {
        ChatLabel(name: name).monogram
    }

    /// The color a space without an icon draws on: an index into a palette
    /// of `paletteCount` colors. Stable for a space ID across launches.
    public func colorIndex(paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        let sum = id.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % paletteCount }
        return sum % paletteCount
    }

    /// The rail's space items: the top-level joined spaces that hold at
    /// least one chat, in the order given, each with its unread mark.
    ///
    /// A space with no chat is left out: it would be a filter that shows
    /// nothing.
    ///
    /// - Parameters:
    ///   - joined: the top-level joined spaces, in the SDK's order. Their
    ///     `badge` is ignored.
    ///   - spaces: the room-to-space map.
    ///   - chatIds: the account's chat rooms.
    ///   - unread: the unread state by room ID. A room with no entry counts
    ///     as read. A room muted by its labels has `isMuted` set.
    ///   - lowPriorityRoomIds: the rooms with the Matrix low priority tag.
    ///     They add nothing to a badge (MATRIX-180).
    public static func items(
        joined: [ChatListRailSpace],
        spaces: RoomSpaceMap,
        chatIds: some Sequence<String>,
        unread: [String: ChatListUnread],
        lowPriorityRoomIds: Set<String> = []
    ) -> [ChatListRailSpace] {
        let roomsBySpace = spaces.roomsBySpace(among: chatIds)
        var seen = Set<String>()
        return joined.compactMap { space in
            guard let rooms = roomsBySpace[space.id], seen.insert(space.id).inserted else { return nil }
            var item = space
            item.badge = ChatLabelBadge.badge(forRooms: rooms, lowPriorityRoomIds: lowPriorityRoomIds, unread: unread)
            return item
        }
    }

    /// The rail's space items from the unread tracker's states (MATRIX-180).
    ///
    /// Each state becomes the unread state of its room. A room muted by its
    /// labels is muted. A room with the low priority tag adds nothing.
    ///
    /// - Parameters:
    ///   - joined: the top-level joined spaces, in the SDK's order.
    ///   - spaces: the room-to-space map.
    ///   - chatIds: the account's chat rooms.
    ///   - chats: the tracker's state by room ID.
    ///   - labelMutedRoomIds: `ChatLabelDocument.labelMutedRoomIds`.
    public static func items(
        joined: [ChatListRailSpace],
        spaces: RoomSpaceMap,
        chatIds: some Sequence<String>,
        chats: [String: UnreadChatState],
        labelMutedRoomIds: Set<String>
    ) -> [ChatListRailSpace] {
        let unread = chats.mapValues { chat in
            ChatListUnread(
                numUnreadMessages: chat.numUnreadMessages,
                numUnreadNotifications: chat.numUnreadNotifications,
                numUnreadMentions: 0,
                isMarkedUnread: chat.isMarkedUnread,
                isMuted: chat.isMuted,
                isMutedByLabel: labelMutedRoomIds.contains(chat.roomId)
            )
        }
        return items(
            joined: joined,
            spaces: spaces,
            chatIds: chatIds,
            unread: unread,
            lowPriorityRoomIds: Set(chats.values.lazy.filter(\.isLowPriority).map(\.roomId))
        )
    }
}

public extension ChatListMerging {
    /// The chats a rail filter shows, with merged chats folded in, split into
    /// the pinned grid and the list (MATRIX-167). The one path for the Inbox,
    /// a space, and a label.
    ///
    /// The steps, in order (MATRIX-141 Phase A note):
    /// 1. Filter.
    ///    - Inbox: drops the rooms of labels hidden from the Inbox
    ///      (MATRIX-77). A label the labels do not hold counts as the Inbox.
    ///    - A label: keeps the label's rooms. A selected label shows all its
    ///      rooms, hidden from the Inbox or not.
    ///    - A space: keeps the rooms the space holds, directly or through
    ///      sub-spaces. A space shows all its rooms, also the rooms of
    ///      labels hidden from the Inbox. A space that holds no entry gives
    ///      an empty list; `ChatListRailFilter.resolved` is what turns an
    ///      unknown space into the Inbox.
    /// 2. Merge. The member rows that are left become one merged row. A
    ///    merged chat shows under a space or a label when any member is in
    ///    it, and then sums only those members.
    /// 3. Split. Favourites go to the grid, the rest to the list.
    ///
    /// MATRIX-206: before step 1, the inbox state keeps only the chats of
    /// `placement`. For the Inbox (every list filter but Archived) that
    /// drops the archived chats, under any rail filter. A merged chat is
    /// one chat (`InboxStateDocument.placement(of:merges:)`).
    ///
    /// The SDK applies the chat-list filter (MATRIX-67) and the same room
    /// narrowing before `entries` arrive, so for a label or a space step 1
    /// drops only rows the SDK has not removed yet.
    ///
    /// - Parameters:
    ///   - entries: the client's chat rooms in SDK (recency) order, without
    ///     spaces, favourites included.
    ///   - filter: the rail filter.
    ///   - labels: the labels document.
    ///   - spaces: the room-to-space map.
    ///   - document: the account's merged chats.
    ///   - inbox: the account's inbox states (MATRIX-206).
    ///   - placement: the inbox placement the list filter shows
    ///     (`ChatListFilter.inboxPlacement`).
    /// - Returns: the pinned grid and the list. `ordered` is what the Go menu
    ///   walks.
    static func visible(
        entries: [ChatListEntry],
        filter: ChatListRailFilter,
        labels: ChatLabelDocument,
        spaces: RoomSpaceMap,
        document: MergedChatDocument,
        inbox: InboxStateDocument = InboxStateDocument(),
        placement: InboxPlacement = .inbox
    ) -> VisibleChatList<ChatListItem> {
        let entries = placementEntries(entries, inbox: inbox, placement: placement, merges: document)
        let shown: [ChatListEntry]
        switch filter {
        case let .space(id):
            shown = entries.filter { spaces.isRoom($0.id, in: id) }
        case let .label(id):
            if let label = labels.label(id: id) {
                let rooms = Set(label.rooms)
                shown = entries.filter { rooms.contains($0.id) }
            } else {
                shown = inboxEntries(entries, labels: labels)
            }
        case .inbox:
            shown = inboxEntries(entries, labels: labels)
        }
        return visible(entries: shown, document: document)
    }

    /// The room IDs a rail filter shows, in the order of the sidebar: the
    /// pinned grid, then the list. A merged chat gives each member the
    /// filter shows. A later broadcast feature sends to these rooms.
    ///
    /// The parameters are those of `visible(entries:filter:labels:spaces:document:)`.
    static func roomIds(
        entries: [ChatListEntry],
        filter: ChatListRailFilter,
        labels: ChatLabelDocument,
        spaces: RoomSpaceMap,
        document: MergedChatDocument
    ) -> [String] {
        visible(entries: entries, filter: filter, labels: labels, spaces: spaces, document: document)
            .ordered
            .flatMap(\.roomIds)
    }

    /// The entries whose inbox placement is `placement` (MATRIX-206).
    private static func placementEntries(
        _ entries: [ChatListEntry],
        inbox: InboxStateDocument,
        placement: InboxPlacement,
        merges: MergedChatDocument
    ) -> [ChatListEntry] {
        if placement == .inbox {
            let hidden = inbox.hiddenRoomIds(merges: merges)
            return hidden.isEmpty ? entries : entries.filter { !hidden.contains($0.id) }
        }
        let kept = inbox.roomIds(in: placement, merges: merges)
        return entries.filter { kept.contains($0.id) }
    }

    private static func inboxEntries(_ entries: [ChatListEntry], labels: ChatLabelDocument) -> [ChatListEntry] {
        let hidden = labels.inboxHiddenRoomIds
        return hidden.isEmpty ? entries : entries.filter { !hidden.contains($0.id) }
    }
}

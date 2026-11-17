import Foundation

/// Why the target list of a broadcast can lack chats of the rail filter
/// (MATRIX-172; contract §11, 2026-11-17).
public struct BroadcastTargetGap: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// The account's room list holds no room: it has not loaded, or it
        /// did not open. The targets are the sidebar's chats only.
        case accountListNotLoaded
        /// The account's room list is full. It holds `limit` rooms at most,
        /// so the account can have chats the list does not hold.
        case accountListFull(limit: Int)
        /// The account's room list is loaded and not full, and it does not
        /// hold a room the filter names, or the client has no data for a
        /// room it holds. The room is not joined, or it has not loaded yet.
        case notInAccountList
    }

    public var reason: Reason
    /// The number of chats that are missing, or nil when it is not known
    /// (a space names its chats only through the room list).
    public var count: Int?

    public init(reason: Reason, count: Int?) {
        self.reason = reason
        self.count = count
    }

    /// One line for the sheet: how many chats are missing and why.
    public var line: String {
        let subject = switch count {
        case .none: "Some chats can be missing"
        case 1: "1 chat is missing"
        case let .some(count): "\(count) chats are missing"
        }
        switch reason {
        case .accountListNotLoaded:
            return "\(subject) because the full chat list is not loaded."
        case let .accountListFull(limit):
            return "\(subject) because the full chat list holds \(limit) chats at most."
        case .notInAccountList:
            return count == 1
                ? "\(subject) because the full chat list does not hold it. It is not joined, or not loaded yet."
                : "\(subject) because the full chat list does not hold them. They are not joined, or not loaded yet."
        }
    }
}

/// The chats a broadcast reads its targets from (MATRIX-172).
public struct BroadcastChatSource {
    /// The sidebar's chat rooms in SDK order, without spaces. They can be
    /// one page, narrowed by the chat-list filter.
    public var sidebarEntries: [ChatListEntry]
    /// Every non-space room of the account's unfiltered room list.
    public var accountChatIds: Set<String>
    /// The most rooms the account's room list holds.
    public var accountListLimit: Int
    /// The chat-list row of a room the sidebar does not hold, or nil when
    /// the client has no data for the room.
    public var row: (String) -> ChatListRowModel?

    public init(
        sidebarEntries: [ChatListEntry],
        accountChatIds: Set<String>,
        accountListLimit: Int,
        row: @escaping (String) -> ChatListRowModel?
    ) {
        self.sidebarEntries = sidebarEntries
        self.accountChatIds = accountChatIds
        self.accountListLimit = accountListLimit
        self.row = row
    }
}

/// The targets of a broadcast and what is known to be missing from them
/// (MATRIX-172; contract §11, 2026-11-17).
///
/// The targets are every chat of the rail filter that the account has. The
/// source is the account's unfiltered room list (the list of the Dock badge
/// tracker), not the sidebar's list: the sidebar holds one page, and the
/// chat-list filter (Unread, People) narrows it.
public struct BroadcastTargetList: Equatable, Sendable {
    public var targets: [BroadcastTarget]
    /// Nil when the list is known to be complete.
    public var gap: BroadcastTargetGap?

    public init(targets: [BroadcastTarget] = [], gap: BroadcastTargetGap? = nil) {
        self.targets = targets
        self.gap = gap
    }

    /// One line for the sheet: where the targets come from.
    /// "All 132 chats of DevObsessed" for a complete list. A list with a gap
    /// does not say "All".
    public func sourceLine(filterName: String) -> String {
        let count = targets.count
        if gap != nil {
            return count == 1 ? "1 chat of \(filterName)" : "\(count) chats of \(filterName)"
        }
        return count == 1 ? "The 1 chat of \(filterName)" : "All \(count) chats of \(filterName)"
    }

    /// The targets of a rail filter from the account's room list.
    ///
    /// The steps:
    /// 1. The filter's rooms come from `ChatListRailFilter.narrowingRoomIds`
    ///    over the account's chat IDs and the sidebar's chat IDs.
    /// 2. A room the sidebar holds keeps its sidebar entry. Each other room
    ///    gets an entry from `source.row`. Those entries go after the
    ///    sidebar's, by title: the account's room list gives no recency.
    /// 3. `BroadcastTarget.targets(entries:filter:labels:spaces:document:now:)`
    ///    makes the targets, so the merged-chat rule is that of
    ///    `ChatListMerging.roomIds`.
    ///
    /// The gap:
    /// - A label names its rooms, so the number of missing chats is known:
    ///   the label's rooms that neither list holds, plus the rooms with no
    ///   row. With none missing there is no gap, whatever the list's state.
    /// - A space names its chats only through the room list. With an empty
    ///   or a full list the gap has no count.
    ///
    /// - Parameters:
    ///   - source: the sidebar's chats and the account's room list.
    ///   - filter: the resolved rail filter.
    ///   - labels: the labels document.
    ///   - spaces: the room-to-space map.
    ///   - document: the account's merged chats.
    ///   - now: the current time, for the send-target rule.
    public static func make(
        source: BroadcastChatSource,
        filter: ChatListRailFilter,
        labels: ChatLabelDocument,
        spaces: RoomSpaceMap,
        document: MergedChatDocument,
        now: Date = .now
    ) -> BroadcastTargetList {
        let accountChatIds = source.accountChatIds
        let sidebarIds = Set(source.sidebarEntries.map(\.id))
        let known = accountChatIds.union(sidebarIds)
        guard let named = filter.narrowingRoomIds(labels: labels, spaces: spaces, chatIds: known) else {
            return BroadcastTargetList()
        }
        let wanted = Set(named)

        var missing = wanted.subtracting(known).count
        var added: [ChatListEntry] = []
        for roomId in wanted.intersection(known).subtracting(sidebarIds) {
            if let row = source.row(roomId) {
                added.append(ChatListEntry(row: row))
            } else {
                missing += 1
            }
        }
        added.sort { first, second in
            let order = first.row.title.localizedStandardCompare(second.row.title)
            return order == .orderedSame ? first.id < second.id : order == .orderedAscending
        }

        let targets = BroadcastTarget.targets(
            entries: source.sidebarEntries + added,
            filter: filter, labels: labels, spaces: spaces, document: document, now: now
        )

        let listState: BroadcastTargetGap.Reason? = if accountChatIds.isEmpty {
            .accountListNotLoaded
        } else if accountChatIds.count >= source.accountListLimit {
            .accountListFull(limit: source.accountListLimit)
        } else {
            nil
        }
        let namesItsRooms = filter.labelId != nil
        var gap: BroadcastTargetGap?
        if namesItsRooms || listState == nil {
            if missing > 0 {
                gap = BroadcastTargetGap(reason: listState ?? .notInAccountList, count: missing)
            }
        } else if let listState {
            gap = BroadcastTargetGap(reason: listState, count: nil)
        }
        return BroadcastTargetList(targets: targets, gap: gap)
    }
}

import Foundation

// MATRIX-142 (M2.5-3): the engine that turns the timelines of a merged
// chat's member rooms into one merged timeline. Pure logic: Phase B's Core
// multi-room timeline feeds it one SDK `Timeline` per member room.

/// One row of the merged timeline (MATRIX-142).
///
/// Every identifier comes from `MergedTimelineEntryID`, so an entry
/// identifier never collides with another entry or with an SDK identifier,
/// and it stays the same across recomputes (the table diff and the row
/// height cache key on it).
public enum MergedTimelineEntry<Item> {
    /// An event or a local echo of the member room `roomId`.
    case item(id: String, roomId: String, item: Item)
    /// The start of the merged history. It shows only when every member
    /// reached its start.
    case timelineStart(id: String)
    /// The first row of a calendar day. `date` is the start of that day in
    /// the merge's calendar.
    case dateDivider(id: String, date: Date)
    /// The merged read marker, directly above the first unread item.
    case readMarker(id: String)
    /// The source note: the items below it, up to the next source note, come
    /// from the member room `roomId`.
    case sourceChange(id: String, roomId: String)

    /// The entry's stable identifier.
    public var id: String {
        switch self {
        case let .item(id, _, _):
            id
        case let .timelineStart(id):
            id
        case let .dateDivider(id, _):
            id
        case let .readMarker(id):
            id
        case let .sourceChange(id, _):
            id
        }
    }

    /// The member room of an item or a source note. Nil for the other
    /// entries, which belong to the whole merged chat.
    public var roomId: String? {
        switch self {
        case let .item(_, roomId, _):
            roomId
        case let .sourceChange(_, roomId):
            roomId
        case .timelineStart, .dateDivider, .readMarker:
            nil
        }
    }
}

extension MergedTimelineEntry: Equatable where Item: Equatable {}
extension MergedTimelineEntry: Sendable where Item: Sendable {}

/// How the merged timeline forms its entry identifiers (MATRIX-142).
///
/// Every identifier starts with `prefix`, then names its kind, so two kinds
/// never collide and no SDK identifier (a counter, or a counter after the
/// timeline's `internalIdPrefix`) is ever equal to one.
///
/// - Items: scoped by room, because the SDK's unique identifiers are unique
///   per timeline only, and the merge has one timeline per member room.
///   The room ID and the item identifier are joined with "|", which a valid
///   room ID never contains after its first ":", so the join is unambiguous.
/// - Source notes: keyed by the first item of the run they label. A new item
///   at the newest end does not change an existing note.
/// - Date dividers: keyed by the calendar day. The merge never emits the same
///   day twice (see `MergedTimelineMerger.merge(_:calendar:)`).
/// - The read marker and the timeline start: one each, fixed.
public enum MergedTimelineEntryID {
    /// The prefix of every merged-timeline identifier.
    public static let prefix = "merged:"

    /// The identifier of the merged timeline start.
    public static let timelineStart = "merged:timeline-start"

    /// The identifier of the merged read marker.
    public static let readMarker = "merged:read-marker"

    /// The identifier of the item `itemId` of the member room `roomId`.
    public static func item(roomId: String, itemId: String) -> String {
        "merged:item:\(roomId)|\(itemId)"
    }

    /// The identifier of the source note above the run that starts with the
    /// item `firstItemId` of the member room `roomId`.
    public static func sourceChange(roomId: String, firstItemId: String) -> String {
        "merged:source:\(roomId)|\(firstItemId)"
    }

    /// The identifier of the date divider of the day that holds `date`, for
    /// example "merged:day:2026-11-10".
    public static func day(of date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = twoDigits(components.month ?? 0)
        let day = twoDigits(components.day ?? 0)
        return "merged:day:\(year)-\(month)-\(day)"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

/// The result of one merge (MATRIX-142).
public struct MergedTimelineContent<Item> {
    /// The merged timeline, oldest first (reading order).
    public let entries: [MergedTimelineEntry<Item>]
    /// The boundary the merge applied at the oldest end.
    public let boundary: MergedTimelineBoundary

    public init(entries: [MergedTimelineEntry<Item>], boundary: MergedTimelineBoundary) {
        self.entries = entries
        self.boundary = boundary
    }

    /// The entries newest first: the display order of the timeline table,
    /// where index 0 is the newest end (S-34). No copy.
    public var newestFirst: ReversedCollection<[MergedTimelineEntry<Item>]> {
        entries.reversed()
    }
}

extension MergedTimelineContent: Equatable where Item: Equatable {}
extension MergedTimelineContent: Sendable where Item: Sendable {}

/// Merges the timelines of a merged chat's member rooms into one timeline
/// (MATRIX-142, contract §4 M2.5).
///
/// Presentation only: it reorders and decorates items the SDK already gave
/// each room. It never makes a Matrix decision (hard rule 1).
public enum MergedTimelineMerger {
    /// Merges the member rooms' timelines into one.
    ///
    /// **Order.** Server events interleave by `origin_server_ts`. On equal
    /// timestamps, the member earlier in `members` goes first. A room's own
    /// items never change order: this is a k-way merge of the rooms' lists
    /// (it compares the heads), not a sort. If a room holds an out-of-order
    /// timestamp, the room's own order wins near that item. Local echoes go
    /// after every server event, ordered by `createdAt`, then by member
    /// order.
    ///
    /// **Clamp.** Server events older than the boundary are hidden (see
    /// `MergedTimelineBoundary`), so the merged view never shows a gap.
    ///
    /// **Dropped.** The SDK's date dividers, read markers, timeline starts,
    /// and other virtual items. The merge makes its own:
    ///
    /// - Timeline start: at the top, when every member reached its start.
    /// - Date dividers: one per calendar day of `calendar`, above the first
    ///   item of that day. A divider is emitted only for a day later than the
    ///   day of the previous divider. An item whose day is earlier (a room's
    ///   out-of-order timestamp, or a local echo from a clock that runs
    ///   behind the server's) stays under the current divider, so a day never
    ///   shows twice and divider identifiers stay unique.
    /// - Read marker: an item is unread when it comes after the SDK read
    ///   marker in its own room's list. The merged marker goes directly above
    ///   the first unread item in the merged order: after the newest item
    ///   that is older than every member's read marker. A member with no read
    ///   marker in its list has no unread items. There is no marker when no
    ///   item is unread, and no marker when the first shown item is unread,
    ///   because then the read position is not loaded (the SDK shows no
    ///   marker in that case either). Read items of other rooms can show
    ///   below the marker.
    /// - Source notes: above the first item of each run of items from one
    ///   room, carrying that room's ID. Above the very first item only when
    ///   the shown items come from two or more rooms; with one room there is
    ///   nothing to tell apart.
    ///
    /// Where several entries go above one item, the order is: read marker,
    /// date divider, source note, item. That is the SDK's order for its read
    /// marker and date divider, and it keeps the note next to its run. A
    /// source note is not a message row, so sender grouping
    /// (`TimelineRowGrouping`) starts a new run below it.
    ///
    /// **Cost.** One pass per member to filter, a k-way merge that compares
    /// at most `k - 1` heads per item, and one pass to decorate: O(N × k) for
    /// N items and k members (k is 2 to 4), with no sort and no insert into
    /// the middle of an array. `mergedItemKind` is read once per item.
    ///
    /// **Contract for the caller (Phase B).**
    ///
    /// - Pass the members in `MergedChat.rooms` order. Ties break by it.
    /// - Pass each member's items in SDK order, oldest first.
    /// - Set `reachedStart` from the SDK pagination status
    ///   (`.idle(hitTimelineStart: true)`).
    /// - Recompute after any change to any member: an item diff, a
    ///   `reachedStart` change, a member added or removed, or a calendar or
    ///   time-zone change. Coalesce: one recompute per batch of diffs, not
    ///   one per diff.
    /// - Cache, per member, the array of conforming items, updated by
    ///   applying each SDK diff (as `LiveTimeline` keeps `timelineItems`).
    ///   The conforming item stores its identifier and kind, so a recompute
    ///   never calls the FFI.
    /// - Cache the previous result. Diff the new entries against it by `id`
    ///   to get the table changes, and reuse the mapped row and the measured
    ///   height of every entry whose `id` is unchanged.
    /// - Use `MergedTimelineEntry.id` as the row identifier. It is not the
    ///   SDK's unique identifier: items are scoped by room
    ///   (`MergedTimelineEntryID.item(roomId:itemId:)`).
    ///
    /// - Parameters:
    ///   - members: the member rooms, in merge order. A repeated room ID is
    ///     ignored after its first appearance.
    ///   - calendar: decides where a day starts. Pass the reader's calendar,
    ///     the one the timeline groups senders with.
    /// - Returns: the merged entries, oldest first, and the boundary used.
    public static func merge<Item: MergedTimelineSourceItem>(
        _ members: [MergedTimelineMember<Item>],
        calendar: Calendar
    ) -> MergedTimelineContent<Item> {
        var stats = MergeStats()
        return merge(members, calendar: calendar, stats: &stats)
    }

    /// The boundary of these members (see `MergedTimelineBoundary`): the
    /// newest of the oldest loaded timestamps among the members that have
    /// not reached their start.
    public static func boundary(
        of members: [MergedTimelineMember<some MergedTimelineSourceItem>]
    ) -> MergedTimelineBoundary {
        boundary(of: histories(of: uniqueMembers(members)))
    }

    /// The member rooms to back-paginate next, so the boundary moves back
    /// (Beeper's "boundary holders").
    ///
    /// Only a member whose oldest loaded event is at the boundary holds the
    /// boundary. Paginating any other member reveals nothing, because its
    /// older events are older than the boundary and stay hidden.
    ///
    /// - Parameters:
    ///   - members: the member rooms, in merge order.
    ///   - tolerance: also return a member whose oldest loaded event is at
    ///     most this many seconds older than the boundary. With 0 (Beeper's
    ///     rule) only the holders paginate, and two members whose oldest
    ///     events are close take turns, one round trip each. A tolerance
    ///     paginates them together. A negative value counts as 0.
    /// - Returns: room IDs in merge order. Empty when the boundary is open.
    ///   When the boundary is pending, the members that have loaded no
    ///   server event yet, because nothing shows until they load one.
    public static func paginationTargets(
        of members: [MergedTimelineMember<some MergedTimelineSourceItem>],
        tolerance: TimeInterval = 0
    ) -> [String] {
        let histories = Self.histories(of: uniqueMembers(members))
        switch Self.boundary(of: histories) {
        case .open:
            return []
        case .pending:
            return histories.filter { !$0.reachedStart && $0.oldestLoaded == nil }.map(\.roomId)
        case let .clamped(at: boundary):
            let earliest = boundary.addingTimeInterval(-max(tolerance, 0))
            return histories.compactMap { history in
                guard !history.reachedStart, let oldest = history.oldestLoaded, oldest >= earliest else { return nil }
                return history.roomId
            }
        }
    }
}

// MARK: - Engine

/// Counters that tests read to check the algorithm's shape.
struct MergeStats {
    /// Comparisons of two lane heads in the k-way merge.
    var keyComparisons = 0
}

extension MergedTimelineMerger {
    /// What the boundary needs to know about one member.
    struct MemberHistory {
        let roomId: String
        let reachedStart: Bool
        let oldestLoaded: Date?
    }

    /// The sort key of a shown item: server events first by server time,
    /// then local echoes by creation time.
    struct MergeKey: Comparable {
        let isLocalEcho: Bool
        let date: Date

        static func < (lhs: MergeKey, rhs: MergeKey) -> Bool {
            if lhs.isLocalEcho != rhs.isLocalEcho {
                return !lhs.isLocalEcho
            }
            return lhs.date < rhs.date
        }
    }

    /// One shown item of one member: where it sits in the member's items,
    /// its sort key, and whether it is unread.
    struct LaneItem {
        let index: Int
        let key: MergeKey
        let isUnread: Bool
    }

    /// One item of the merged order: the member it comes from, and the item.
    struct Pick {
        let lane: Int
        let item: LaneItem
    }

    /// `merge(_:calendar:)`, with counters for tests.
    static func merge<Item: MergedTimelineSourceItem>(
        _ members: [MergedTimelineMember<Item>],
        calendar: Calendar,
        stats: inout MergeStats
    ) -> MergedTimelineContent<Item> {
        let members = uniqueMembers(members)
        let boundary = Self.boundary(of: histories(of: members))
        let lanes = members.map { lane(of: $0, boundary: boundary) }
        let picks = interleave(lanes, stats: &stats)
        let showsTimelineStart = !members.isEmpty && members.allSatisfy(\.reachedStart)
        let entries = decorate(picks, members: members, showsTimelineStart: showsTimelineStart, calendar: calendar)
        return MergedTimelineContent(entries: entries, boundary: boundary)
    }

    /// The members without a repeated room ID. A repeated room would repeat
    /// every item identifier, and the table cannot hold a repeated identifier
    /// (MATRIX-130).
    static func uniqueMembers<Item>(_ members: [MergedTimelineMember<Item>]) -> [MergedTimelineMember<Item>] {
        var seen = Set<String>()
        return members.filter { seen.insert($0.roomId).inserted }
    }

    static func histories(of members: [MergedTimelineMember<some Any>]) -> [MemberHistory] {
        members.map { member in
            MemberHistory(roomId: member.roomId, reachedStart: member.reachedStart, oldestLoaded: member.oldestLoadedTimestamp)
        }
    }

    static func boundary(of histories: [MemberHistory]) -> MergedTimelineBoundary {
        var newestOldest: Date?
        for history in histories where !history.reachedStart {
            guard let oldest = history.oldestLoaded else { return .pending }
            if let current = newestOldest, current >= oldest {
                continue
            }
            newestOldest = oldest
        }
        guard let newestOldest else { return .open }
        return .clamped(at: newestOldest)
    }

    /// The shown items of one member, in the member's own order, with their
    /// unread state. One pass over every item, hidden ones included, because
    /// a read marker can sit among the hidden items.
    static func lane(of member: MergedTimelineMember<some Any>, boundary: MergedTimelineBoundary) -> [LaneItem] {
        var lane: [LaneItem] = []
        lane.reserveCapacity(member.items.count)
        var afterReadMarker = false
        for (index, item) in member.items.enumerated() {
            switch item.mergedItemKind {
            case let .event(serverTimestamp):
                guard !boundary.hides(serverTimestamp: serverTimestamp) else { continue }
                let key = MergeKey(isLocalEcho: false, date: serverTimestamp)
                lane.append(LaneItem(index: index, key: key, isUnread: afterReadMarker))
            case let .localEcho(createdAt):
                let key = MergeKey(isLocalEcho: true, date: createdAt)
                lane.append(LaneItem(index: index, key: key, isUnread: afterReadMarker))
            case .readMarker:
                afterReadMarker = true
            case .dateDivider, .otherVirtual:
                continue
            }
        }
        return lane
    }

    /// The k-way merge: repeatedly takes the lane whose head has the smallest
    /// key, the earlier lane on a tie.
    static func interleave(_ lanes: [[LaneItem]], stats: inout MergeStats) -> [Pick] {
        var cursors = Array(repeating: 0, count: lanes.count)
        var picks: [Pick] = []
        picks.reserveCapacity(lanes.reduce(0) { $0 + $1.count })
        while let lane = nextLane(lanes, cursors: cursors, stats: &stats) {
            picks.append(Pick(lane: lane, item: lanes[lane][cursors[lane]]))
            cursors[lane] += 1
        }
        return picks
    }

    /// The lane whose head goes next, or nil when every lane is empty.
    private static func nextLane(_ lanes: [[LaneItem]], cursors: [Int], stats: inout MergeStats) -> Int? {
        var best: Int?
        for lane in lanes.indices where cursors[lane] < lanes[lane].count {
            guard let current = best else {
                best = lane
                continue
            }
            stats.keyComparisons += 1
            if lanes[lane][cursors[lane]].key < lanes[current][cursors[current]].key {
                best = lane
            }
        }
        return best
    }

    /// Turns the merged order into entries, with the timeline start, the
    /// read marker, the date dividers, and the source notes.
    static func decorate<Item: MergedTimelineSourceItem>(
        _ picks: [Pick],
        members: [MergedTimelineMember<Item>],
        showsTimelineStart: Bool,
        calendar: Calendar
    ) -> [MergedTimelineEntry<Item>] {
        var entries: [MergedTimelineEntry<Item>] = []
        entries.reserveCapacity(picks.count * 2)
        if showsTimelineStart {
            entries.append(.timelineStart(id: MergedTimelineEntryID.timelineStart))
        }
        let readMarkerPosition = Self.readMarkerPosition(in: picks)
        let firstLane = picks.first?.lane
        let labelsFirstRun = picks.contains { $0.lane != firstLane }
        var days = DayCursor(calendar: calendar)
        var previousLane: Int?
        for (position, pick) in picks.enumerated() {
            let member = members[pick.lane]
            let item = member.items[pick.item.index]
            let itemId = item.mergedItemId
            if position == readMarkerPosition {
                entries.append(.readMarker(id: MergedTimelineEntryID.readMarker))
            }
            if let dayStart = days.newDayStart(for: pick.item.key.date) {
                entries.append(.dateDivider(id: MergedTimelineEntryID.day(of: dayStart, calendar: calendar), date: dayStart))
            }
            if pick.lane != previousLane, previousLane != nil || labelsFirstRun {
                let noteId = MergedTimelineEntryID.sourceChange(roomId: member.roomId, firstItemId: itemId)
                entries.append(.sourceChange(id: noteId, roomId: member.roomId))
            }
            let id = MergedTimelineEntryID.item(roomId: member.roomId, itemId: itemId)
            entries.append(.item(id: id, roomId: member.roomId, item: item))
            previousLane = pick.lane
        }
        return entries
    }

    /// Where the merged read marker goes: the position of the first unread
    /// item, or nil when no item is unread or the first item is unread.
    static func readMarkerPosition(in picks: [Pick]) -> Int? {
        guard let first = picks.firstIndex(where: \.item.isUnread), first > 0 else { return nil }
        return first
    }
}

/// Finds where a new calendar day starts along the merged order, and never
/// goes back to an earlier day.
struct DayCursor {
    let calendar: Calendar
    private var nextDayStart: Date?

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// The start of the day of `date` when that day is later than the
    /// current day, else nil. One calendar call per new day, two date
    /// comparisons per item.
    mutating func newDayStart(for date: Date) -> Date? {
        if let nextDayStart, date < nextDayStart {
            return nil
        }
        let dayStart = calendar.startOfDay(for: date)
        nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
        return dayStart
    }
}

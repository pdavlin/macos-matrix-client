import Foundation

// MATRIX-142 Phase B: turns the merge engine's entries (MergedTimeline.swift)
// into the rows the timeline container draws. Pure logic, so it is tested
// without the SDK. Core's `MergedLiveTimeline` feeds it.

// MARK: - Source note label

/// What the merged timeline's source note says about one member room
/// (MATRIX-142). `UI.MergedSourceNote` draws it.
///
/// The label rule (orchestrator decision, MATRIX-142 Phase B): when the
/// room's bridged network is known, the title is the network's name and the
/// detail is the room's display name ("Slack • Seth"). When the network is
/// not known, the title is the room's display name and there is no detail.
/// A room without a display name shows its room ID.
public struct MergedSourceLabel: Hashable, Sendable {
    /// The row height of a source note, at every width and for every label.
    /// It must equal `MergedSourceNoteToken.height` (Tokens), which the view
    /// uses; a UI test checks that the two agree.
    public static let rowHeight: CGFloat = 28

    /// The member room the note labels.
    public var roomId: String
    /// The room's bridged network (`ChatListNetwork.detect`), or nil.
    public var network: ChatListNetwork?
    /// The first part of the label.
    public var title: String
    /// The part after " • ", or nil.
    public var detail: String?
    /// The room's account (MATRIX-148). Its icon is the note's badge.
    public var account: ChatAccount?

    public init(roomId: String, network: ChatListNetwork?, title: String, detail: String?) {
        self.roomId = roomId
        self.network = network
        self.title = title
        self.detail = detail
    }

    /// Applies the label rule.
    ///
    /// - Parameters:
    ///   - roomId: the member room's ID.
    ///   - network: the room's network, from the chat list's badge logic.
    ///   - roomName: the room's display name. Nil or blank counts as none.
    public init(roomId: String, network: ChatListNetwork?, roomName: String?, account: ChatAccount? = nil) {
        self.init(roomId: roomId, network: network, roomName: roomName)
        self.account = account
    }

    public init(roomId: String, network: ChatListNetwork?, roomName: String?) {
        let name = roomName.flatMap { raw -> String? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let network {
            self.init(roomId: roomId, network: network, title: network.displayName, detail: name)
        } else {
            self.init(roomId: roomId, network: nil, title: name ?? roomId, detail: nil)
        }
    }
}

// MARK: - Row identity

public extension TimelineRow {
    /// The same row with another identifier. The merged timeline uses it to
    /// give a member room's row its merged identifier
    /// (`MergedTimelineEntryID`).
    func withUniqueId(_ uniqueId: String) -> TimelineRow {
        switch self {
        case let .message(_, event, kind, fingerprint):
            .message(uniqueId: uniqueId, event: event, kind: kind, heightFingerprint: fingerprint)
        case let .state(_, event, name):
            .state(uniqueId: uniqueId, event: event, name: name)
        case let .virtual(_, item):
            .virtual(uniqueId: uniqueId, item: item)
        case let .typingIndicator(_, names):
            .typingIndicator(uniqueId: uniqueId, names: names)
        case .paginationActivity:
            .paginationActivity(uniqueId: uniqueId)
        case let .paginationFailure(_, message):
            .paginationFailure(uniqueId: uniqueId, message: message)
        case .unsupported:
            .unsupported(uniqueId: uniqueId)
        }
    }
}

public extension MergedTimelineEntryID {
    /// The prefix of every item identifier (`item(roomId:itemId:)`).
    private static let itemPrefix = "merged:item:"
    /// The prefix of every source note identifier
    /// (`sourceChange(roomId:firstItemId:)`).
    private static let sourcePrefix = "merged:source:"

    /// The member room of an item row or a source note row.
    ///
    /// The room is found among `rooms`, not parsed out, so a room ID that
    /// holds "|" in its opaque part cannot confuse it. Cost: at most one
    /// prefix check per member room.
    ///
    /// - Parameters:
    ///   - rowId: a merged row identifier.
    ///   - rooms: the merge's member room IDs.
    /// - Returns: the room, or nil for any other row (a date divider, the
    ///   read marker, the timeline start) and for a room not in `rooms`.
    static func roomId(ofRowId rowId: String, among rooms: [String]) -> String? {
        let rest: Substring
        if rowId.hasPrefix(itemPrefix) {
            rest = rowId.dropFirst(itemPrefix.count)
        } else if rowId.hasPrefix(sourcePrefix) {
            rest = rowId.dropFirst(sourcePrefix.count)
        } else {
            return nil
        }
        return rooms.first { roomId in
            rest.hasPrefix(roomId) && rest.dropFirst(roomId.count).first == "|"
        }
    }

    /// The member room's own item identifier (the SDK's unique identifier)
    /// in an item row identifier, or nil when `rowId` is not an item of
    /// `roomId`.
    static func itemId(ofRowId rowId: String, inRoom roomId: String) -> String? {
        let prefix = itemPrefix + roomId + "|"
        guard rowId.hasPrefix(prefix) else { return nil }
        return String(rowId.dropFirst(prefix.count))
    }
}

// MARK: - Rows

/// One item of a member room's timeline that the merged timeline can draw
/// (MATRIX-142 Phase B).
///
/// Like `MergedTimelineSourceItem`, conform with stored properties: the row
/// builder reads them once per item per recompute.
public protocol MergedTimelineRowItem: MergedTimelineSourceItem {
    /// The item's row before grouping. Its identifier should already be the
    /// merged one (`MergedTimelineEntryID.item(roomId:itemId:)`); the builder
    /// replaces any other identifier.
    var mergedRow: TimelineRow { get }
    /// A value that changes whenever the SDK replaces the item's content (a
    /// reaction, an edit, a send state). The diff reloads a row whose
    /// revision changed.
    var mergedContentRevision: Int { get }
    /// The event ID a read receipt for this item names: set for a server
    /// event only, nil for a local echo and a virtual item.
    var mergedReceiptEventId: String? { get }
}

/// One row of the merged timeline as the model publishes it: the row the
/// container draws, and what the model needs to route it (MATRIX-142 Phase
/// B).
public struct MergedDisplayRow {
    /// The row, grouped, with its merged identifier.
    public let row: TimelineRow
    /// The member room of an item or a source note. Nil for the rows of the
    /// whole merged chat (date dividers, the read marker, the timeline start).
    public let roomId: String?
    /// The event ID a read receipt for this row names, or nil.
    public let receiptEventId: String?
    /// The server time of an item that is a server event, or nil.
    public let serverTimestamp: Date?
    /// The item's content revision (`MergedTimelineRowItem`). 0 for the
    /// other rows, whose identifier fixes their content, and for source
    /// notes, whose content is their label.
    public let contentRevision: Int

    public init(
        row: TimelineRow,
        roomId: String? = nil,
        receiptEventId: String? = nil,
        serverTimestamp: Date? = nil,
        contentRevision: Int = 0
    ) {
        self.row = row
        self.roomId = roomId
        self.receiptEventId = receiptEventId
        self.serverTimestamp = serverTimestamp
        self.contentRevision = contentRevision
    }

    /// The row identifier: the merged entry identifier.
    public var id: String { row.uniqueId }

    /// The label of a source note row, or nil.
    public var sourceLabel: MergedSourceLabel? {
        guard case let .virtual(_, .mergedSource(label)) = row else { return nil }
        return label
    }

    /// True when `other`, a row with the same identifier, draws the same:
    /// same item revision, same grouping, and same source label. The diff
    /// reloads a row for which this is false.
    public func hasSameContent(as other: MergedDisplayRow) -> Bool {
        contentRevision == other.contentRevision
            && row.grouping == other.row.grouping
            && sourceLabel == other.sourceLabel
    }
}

/// Turns the merge engine's entries into the rows the timeline container
/// draws (MATRIX-142 Phase B).
public enum MergedTimelineRowBuilder {
    /// The rows of a merge, newest first: the display order of
    /// `LiveTimeline.displayItems`, so the merged timeline is a drop-in row
    /// source for the same container.
    ///
    /// - Items keep the member room's row, with the merged identifier.
    /// - The merge's date dividers, read marker, and timeline start become
    ///   `.virtual` rows. A source note becomes a `.virtual(.mergedSource)`
    ///   row with the member room's label.
    /// - Every message row is grouped against the row before it in time
    ///   (`TimelineRowGrouping`, MATRIX-68). A source note sits between two
    ///   runs from different rooms and is not a message, so a sender run
    ///   always breaks where the room changes.
    ///
    /// Cost: one pass over the entries, no FFI (the items hold stored rows).
    ///
    /// - Parameters:
    ///   - content: the merge result.
    ///   - labels: the source label per member room ID. A missing room gets a
    ///     label with its room ID as the title.
    ///   - calendar: the calendar the merge used, for the grouping's day rule.
    /// - Returns: the rows, newest first.
    public static func displayRows(
        from content: MergedTimelineContent<some MergedTimelineRowItem>,
        labels: [String: MergedSourceLabel],
        calendar: Calendar
    ) -> [MergedDisplayRow] {
        var rows: [MergedDisplayRow] = []
        rows.reserveCapacity(content.entries.count)
        var predecessor: TimelineRow?
        var days = TimelineDayCache(calendar: calendar)
        for entry in content.entries {
            let display = displayRow(for: entry, labels: labels, predecessor: predecessor, days: &days)
            rows.append(display)
            predecessor = display.row
        }
        rows.reverse()
        return rows
    }

    private static func displayRow(
        for entry: MergedTimelineEntry<some MergedTimelineRowItem>,
        labels: [String: MergedSourceLabel],
        predecessor: TimelineRow?,
        days: inout TimelineDayCache
    ) -> MergedDisplayRow {
        switch entry {
        case let .item(id, roomId, item):
            var row = item.mergedRow
            if row.uniqueId != id {
                row = row.withUniqueId(id)
            }
            let serverTimestamp: Date? = if case let .event(timestamp) = item.mergedItemKind {
                timestamp
            } else {
                nil
            }
            let grouped = row.regrouped(after: predecessor) { (date: Date, other: Date) -> Bool in
                days.isSameDay(date, other)
            }
            return MergedDisplayRow(
                row: grouped,
                roomId: roomId,
                receiptEventId: item.mergedReceiptEventId,
                serverTimestamp: serverTimestamp,
                contentRevision: item.mergedContentRevision
            )
        case let .timelineStart(id):
            return MergedDisplayRow(row: .virtual(uniqueId: id, item: .timelineStart))
        case let .dateDivider(id, date):
            return MergedDisplayRow(row: .virtual(uniqueId: id, item: .dateDivider(date: date)))
        case let .readMarker(id):
            return MergedDisplayRow(row: .virtual(uniqueId: id, item: .readMarker))
        case let .sourceChange(id, roomId):
            let label = labels[roomId] ?? MergedSourceLabel(roomId: roomId, network: nil, roomName: nil)
            return MergedDisplayRow(row: .virtual(uniqueId: id, item: .mergedSource(label)), roomId: roomId)
        }
    }

    /// The row changes from `old` to `new`, both newest first, with the rows
    /// each change brings (see `TimelineRowDiff`).
    public static func updates(from old: [MergedDisplayRow], to new: [MergedDisplayRow]) -> [TimelineRowDisplayUpdate] {
        TimelineRowDiff.updates(
            from: old,
            to: new,
            id: { (row: MergedDisplayRow) -> String in row.id },
            hasSameContent: { (lhs: MergedDisplayRow, rhs: MergedDisplayRow) -> Bool in lhs.hasSameContent(as: rhs) },
            row: { (row: MergedDisplayRow) -> TimelineRow in row.row }
        )
    }
}

/// Answers "the same calendar day" for many date pairs in time order, with
/// one calendar call per day instead of one per pair (MATRIX-142).
///
/// It caches the day interval (`Calendar.dateInterval(of:for:)`) of the last
/// date it was asked about, so the answer is the one
/// `Calendar.isDate(_:inSameDayAs:)` gives, daylight-saving days included.
public struct TimelineDayCache {
    public let calendar: Calendar
    private var day: Range<Date>?

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// True when `date` and `other` fall on the same day of `calendar`.
    /// Reads the day of `other` from the cache when it holds it.
    public mutating func isSameDay(_ date: Date, _ other: Date) -> Bool {
        if let day, day.contains(other) {
            return day.contains(date)
        }
        guard let interval = calendar.dateInterval(of: .day, for: other), interval.duration > 0 else {
            return calendar.isDate(date, inSameDayAs: other)
        }
        let range = interval.start ..< interval.end
        day = range
        return range.contains(date)
    }
}

// MARK: - Read receipts

/// The event a member room's read receipt would name, with its server time.
public struct MergedReceiptCandidate: Hashable, Sendable {
    public var eventId: String
    public var serverTimestamp: Date

    public init(eventId: String, serverTimestamp: Date) {
        self.eventId = eventId
        self.serverTimestamp = serverTimestamp
    }
}

/// Maps the newest visible merged row to one read receipt per member room
/// (MATRIX-142 Phase B, with `MergedChatRouting.readReceipts`).
public enum MergedReadReceiptMapping {
    /// The newest visible server event of each member room.
    ///
    /// Every row at or older than the newest visible row counts as seen: the
    /// reader scrolled past it. So each room's newest visible event is its
    /// first server event at or after `newestVisibleIndex` in the
    /// newest-first rows.
    ///
    /// Cost: a walk from `newestVisibleIndex` toward the oldest row that
    /// stops when every room has an event.
    ///
    /// - Parameters:
    ///   - rows: the merged rows, newest first.
    ///   - newestVisibleIndex: the index of the newest visible row in `rows`.
    ///     A negative index counts as 0.
    ///   - rooms: the merge's member room IDs.
    /// - Returns: the candidate per room ID. A room with no visible server
    ///   event is missing.
    public static func newestVisibleEvents(
        in rows: [MergedDisplayRow],
        newestVisibleIndex: Int,
        rooms: [String]
    ) -> [String: MergedReceiptCandidate] {
        let start = max(newestVisibleIndex, 0)
        guard start < rows.count else { return [:] }
        let wanted = Set(rooms)
        var found: [String: MergedReceiptCandidate] = [:]
        for row in rows[start...] {
            guard let roomId = row.roomId,
                  let eventId = row.receiptEventId,
                  let serverTimestamp = row.serverTimestamp,
                  found[roomId] == nil,
                  wanted.contains(roomId)
            else { continue }
            found[roomId] = MergedReceiptCandidate(eventId: eventId, serverTimestamp: serverTimestamp)
            if found.count == wanted.count { break }
        }
        return found
    }

    /// The candidates that move each room's receipt forward.
    ///
    /// A candidate is dropped when it names the event of the last sent
    /// receipt, or an event older than it. Scrolling up must not send a
    /// receipt for an older event.
    ///
    /// - Parameters:
    ///   - candidates: the newest visible event per room ID.
    ///   - lastSent: the last receipt sent per room ID.
    /// - Returns: the event ID per room ID to send a receipt for.
    public static func advancing(
        _ candidates: [String: MergedReceiptCandidate],
        past lastSent: [String: MergedReceiptCandidate]
    ) -> [String: String] {
        var result: [String: String] = [:]
        for (roomId, candidate) in candidates {
            guard let last = lastSent[roomId] else {
                result[roomId] = candidate.eventId
                continue
            }
            if candidate.eventId != last.eventId, candidate.serverTimestamp >= last.serverTimestamp {
                result[roomId] = candidate.eventId
            }
        }
        return result
    }
}

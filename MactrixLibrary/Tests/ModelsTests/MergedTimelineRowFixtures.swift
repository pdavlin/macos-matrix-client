import Foundation
@testable import Models

/// A member-room item that carries a row, as Core's `MergedLiveItem` does
/// (MATRIX-142 Phase B).
struct RowTestItem: MergedTimelineRowItem {
    let mergedItemId: String
    let mergedItemKind: MergedTimelineItemKind
    let mergedRow: TimelineRow
    var mergedContentRevision: Int
    let mergedReceiptEventId: String?
}

/// Builders for the merged-row tests. A suite conforms to use them without a
/// prefix. Dates, rooms, and the calendar come from `MergedTimelineFixtures`.
protocol MergedTimelineRowFixtures: MergedTimelineFixtures {}

extension MergedTimelineRowFixtures {
    var ada: String { "@ada:example.org" }
    var bob: String { "@bob:example.org" }

    /// A message of `sender` in `room`, `minutes` after `morning`. Its row
    /// carries the merged identifier, as Core builds it; the receipt event
    /// ID is "$" plus the item ID.
    func message(
        _ id: String,
        in room: String,
        from sender: String,
        minutes: Double,
        revision: Int = 0
    ) -> RowTestItem {
        let date = date(minutes: minutes)
        return RowTestItem(
            mergedItemId: id,
            mergedItemKind: .event(serverTimestamp: date),
            mergedRow: .message(
                uniqueId: MergedTimelineEntryID.item(roomId: room, itemId: id),
                event: GroupingTestEvent(sender: sender, date: date),
                kind: .text,
                heightFingerprint: .stub()
            ),
            mergedContentRevision: revision,
            mergedReceiptEventId: "$" + id
        )
    }

    /// A local echo of the account's own user in `room`.
    func localEcho(_ id: String, in room: String, minutes: Double) -> RowTestItem {
        let date = date(minutes: minutes)
        return RowTestItem(
            mergedItemId: id,
            mergedItemKind: .localEcho(createdAt: date),
            mergedRow: .message(
                uniqueId: MergedTimelineEntryID.item(roomId: room, itemId: id),
                event: GroupingTestEvent(sender: ada, date: date, isOwn: true),
                kind: .text,
                heightFingerprint: .stub()
            ),
            mergedContentRevision: 0,
            mergedReceiptEventId: nil
        )
    }

    /// The SDK's read marker in a member room.
    func sdkReadMarker(_ id: String = "rm") -> RowTestItem {
        RowTestItem(
            mergedItemId: id,
            mergedItemKind: .readMarker,
            mergedRow: .virtual(uniqueId: id, item: .readMarker),
            mergedContentRevision: 0,
            mergedReceiptEventId: nil
        )
    }

    func rowMember(_ roomId: String, _ items: [RowTestItem], reachedStart: Bool = false) -> MergedTimelineMember<RowTestItem> {
        MergedTimelineMember(roomId: roomId, items: items, reachedStart: reachedStart)
    }

    /// Merges and builds the rows, newest first.
    func displayRows(
        _ members: [MergedTimelineMember<RowTestItem>],
        labels: [String: MergedSourceLabel] = [:]
    ) -> [MergedDisplayRow] {
        let content = MergedTimelineMerger.merge(members, calendar: calendar)
        return MergedTimelineRowBuilder.displayRows(from: content, labels: labels, calendar: calendar)
    }

    /// One short string per row, newest first: an item's own identifier,
    /// "start", "read", "day", or "note:<room ID>".
    func render(_ rows: [MergedDisplayRow]) -> [String] {
        rows.map { row in
            switch row.row {
            case let .message(uniqueId, _, _, _), let .state(uniqueId, _, _), let .unsupported(uniqueId):
                String(uniqueId.split(separator: "|").last ?? "")
            case let .virtual(_, item):
                switch item {
                case .timelineStart: "start"
                case .readMarker: "read"
                case .dateDivider: "day"
                case let .mergedSource(label): "note:" + label.roomId
                }
            case .typingIndicator, .paginationActivity, .paginationFailure:
                "decoration"
            }
        }
    }

    /// Whether the row draws the sender header. Nil for a row that is not a
    /// message.
    func showsHeader(_ row: MergedDisplayRow) -> Bool? {
        row.row.grouping?.showsProfileHeader
    }
}

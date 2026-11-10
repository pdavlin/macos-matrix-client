import Foundation
@testable import Models

/// A member-room item with a fixed identifier and kind (MATRIX-142).
struct MergeTestItem: MergedTimelineSourceItem, Equatable {
    let mergedItemId: String
    let mergedItemKind: MergedTimelineItemKind
}

/// Builders and a compact rendering for the merged-timeline tests. A test
/// suite conforms to use them without a prefix.
protocol MergedTimelineFixtures {}

extension MergedTimelineFixtures {
    /// Room IDs, short so the rendered entries stay readable.
    var roomA: String { "!a" }
    var roomB: String { "!b" }
    var roomC: String { "!c" }

    /// A fixed zone, so "the same day" does not depend on the machine.
    var calendar: Calendar { zonedCalendar("UTC") }

    /// 2026-11-10 09:00:00 UTC.
    var morning: Date { Date(timeIntervalSince1970: 1_794_301_200) }

    func zonedCalendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        return calendar
    }

    func date(minutes: Double) -> Date {
        morning.addingTimeInterval(minutes * 60)
    }

    /// A server event `minutes` after `morning`.
    func event(_ id: String, minutes: Double) -> MergeTestItem {
        MergeTestItem(mergedItemId: id, mergedItemKind: .event(serverTimestamp: date(minutes: minutes)))
    }

    /// A local echo created `minutes` after `morning`.
    func echo(_ id: String, minutes: Double) -> MergeTestItem {
        MergeTestItem(mergedItemId: id, mergedItemKind: .localEcho(createdAt: date(minutes: minutes)))
    }

    func readMarker(_ id: String = "rm") -> MergeTestItem {
        MergeTestItem(mergedItemId: id, mergedItemKind: .readMarker)
    }

    func dateDivider(_ id: String = "dd") -> MergeTestItem {
        MergeTestItem(mergedItemId: id, mergedItemKind: .dateDivider)
    }

    func otherVirtual(_ id: String = "start") -> MergeTestItem {
        MergeTestItem(mergedItemId: id, mergedItemKind: .otherVirtual)
    }

    func member(
        _ roomId: String,
        _ items: [MergeTestItem],
        reachedStart: Bool = false
    ) -> MergedTimelineMember<MergeTestItem> {
        MergedTimelineMember(roomId: roomId, items: items, reachedStart: reachedStart)
    }

    /// Merges with `calendar` unless the test passes another one.
    func merge(
        _ members: [MergedTimelineMember<MergeTestItem>],
        calendar other: Calendar? = nil
    ) -> MergedTimelineContent<MergeTestItem> {
        MergedTimelineMerger.merge(members, calendar: other ?? calendar)
    }

    /// One short string per entry: the item's own identifier, "start",
    /// "read", "day:<yyyy-MM-dd>", or "note:<room ID>".
    func render(_ content: MergedTimelineContent<MergeTestItem>) -> [String] {
        content.entries.map(render(entry:))
    }

    func render(entry: MergedTimelineEntry<MergeTestItem>) -> String {
        switch entry {
        case let .item(_, _, item):
            item.mergedItemId
        case .timelineStart:
            "start"
        case .readMarker:
            "read"
        case let .dateDivider(id, _):
            "day:" + id.dropFirst("merged:day:".count)
        case let .sourceChange(_, roomId):
            "note:" + roomId
        }
    }

    /// The identifiers of the items, in merged order.
    func items(_ content: MergedTimelineContent<MergeTestItem>) -> [String] {
        content.entries.compactMap { entry in
            guard case let .item(_, _, item) = entry else { return nil }
            return item.mergedItemId
        }
    }
}

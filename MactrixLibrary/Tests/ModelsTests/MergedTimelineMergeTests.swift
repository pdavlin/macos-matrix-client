import Foundation
@testable import Models
import Testing

/// MATRIX-142: the merged timeline's order, timeline start, date dividers,
/// and identifiers. The read marker and the source notes are in
/// `MergedTimelineMarkerTests`; the clamp and pagination are in
/// `MergedTimelinePaginationTests`.
struct MergedTimelineMergeTests: MergedTimelineFixtures {
    // MARK: Order

    @Test func interleavesServerEventsByTimestamp() {
        let content = merge([
            member(roomA, [event("a1", minutes: 0), event("a2", minutes: 10)], reachedStart: true),
            member(roomB, [event("b1", minutes: 5), event("b2", minutes: 15)], reachedStart: true),
        ])
        #expect(render(content) == [
            "start", "day:2026-11-10",
            "note:!a", "a1", "note:!b", "b1", "note:!a", "a2", "note:!b", "b2",
        ])
    }

    @Test func equalTimestampsGoInMemberOrderThenRoomOrder() {
        let first = member(roomA, [event("a1", minutes: 0), event("a2", minutes: 0)], reachedStart: true)
        let second = member(roomB, [event("b1", minutes: 0)], reachedStart: true)
        #expect(items(merge([first, second])) == ["a1", "a2", "b1"])
        #expect(items(merge([second, first])) == ["b1", "a1", "a2"])
    }

    /// A room's own order wins over its timestamps: the merge compares the
    /// heads of the rooms' lists and never sorts a room's items.
    @Test func keepsEachRoomsOwnOrderWhenItsTimestampsGoBackwards() {
        let content = merge([
            member(roomA, [event("a1", minutes: 10), event("a2", minutes: 2)], reachedStart: true),
            member(roomB, [event("b1", minutes: 5)], reachedStart: true),
        ])
        #expect(items(content) == ["b1", "a1", "a2"])
    }

    @Test func localEchoesGoToTheNewestEndInSendOrder() {
        let content = merge([
            member(roomA, [event("a1", minutes: 0), echo("echoA", minutes: 1)], reachedStart: true),
            // Created before the newest server event, still after it.
            member(roomB, [event("b1", minutes: 30), echo("echoB", minutes: 0.5)], reachedStart: true),
        ])
        #expect(items(content) == ["a1", "b1", "echoB", "echoA"])
    }

    @Test func localEchoesWithEqualTimesGoInMemberOrder() {
        let content = merge([
            member(roomA, [echo("echoA", minutes: 1)], reachedStart: true),
            member(roomB, [echo("echoB", minutes: 1)], reachedStart: true),
        ])
        #expect(items(content) == ["echoA", "echoB"])
    }

    /// The SDK keeps an item's unique identifier when its local echo becomes
    /// the remote echo, so the merged row keeps its identity too.
    @Test func localEchoKeepsItsIdentifierWhenItBecomesRemote() {
        let sending = merge([member(roomA, [event("a1", minutes: 0), echo("t1", minutes: 1)], reachedStart: true)])
        let sent = merge([member(roomA, [event("a1", minutes: 0), event("t1", minutes: 1)], reachedStart: true)])
        let id = MergedTimelineEntryID.item(roomId: roomA, itemId: "t1")
        #expect(sending.entries.map(\.id).contains(id))
        #expect(sending.entries.map(\.id) == sent.entries.map(\.id))
    }

    @Test func dropsTheVirtualItemsOfTheSDK() {
        let content = merge([
            member(roomA, [otherVirtual(), dateDivider("a-dd"), event("a1", minutes: 0)], reachedStart: true),
            member(roomB, [dateDivider("b-dd"), event("b1", minutes: 5), otherVirtual("unsupported")], reachedStart: true),
        ])
        #expect(render(content) == ["start", "day:2026-11-10", "note:!a", "a1", "note:!b", "b1"])
    }

    @Test func noMembersMergeToNothing() {
        let content = merge([])
        #expect(content.entries.isEmpty)
        #expect(content.boundary == .open)
    }

    @Test func aRepeatedRoomIsIgnoredAfterItsFirstAppearance() {
        let content = merge([
            member(roomA, [event("a1", minutes: 0)], reachedStart: true),
            member(roomA, [event("a1", minutes: 0), event("a2", minutes: 1)], reachedStart: true),
        ])
        #expect(items(content) == ["a1"])
    }

    @Test func newestFirstIsTheReverseOfTheEntries() {
        let content = merge([
            member(roomA, [event("a1", minutes: 0)], reachedStart: true),
            member(roomB, [event("b1", minutes: 5)], reachedStart: true),
        ])
        #expect(content.newestFirst.map(\.id) == content.entries.map(\.id).reversed())
        #expect(content.newestFirst.first.map(render(entry:)) == "b1")
    }

    // MARK: Timeline start

    @Test func timelineStartShowsOnlyWhenEveryMemberReachedItsStart() {
        let atStart = member(roomA, [event("a1", minutes: 0)], reachedStart: true)
        let notAtStart = member(roomB, [event("b1", minutes: 0)])
        #expect(render(merge([atStart, notAtStart])).first == "day:2026-11-10")
        let both = member(roomB, [event("b1", minutes: 0)], reachedStart: true)
        #expect(render(merge([atStart, both])).first == "start")
    }

    // MARK: Date dividers

    @Test func oneDateDividerAboveTheFirstItemOfEachDay() {
        // 2026-11-09 23:30 UTC, then 2026-11-10 09:00 and 10:00 UTC.
        let content = merge([
            member(roomA, [event("a1", minutes: -570), event("a2", minutes: 0)], reachedStart: true),
            member(roomB, [event("b1", minutes: 60)], reachedStart: true),
        ])
        #expect(render(content) == [
            "start", "day:2026-11-09", "note:!a", "a1",
            "day:2026-11-10", "a2", "note:!b", "b1",
        ])
    }

    @Test func dateDividerDateIsTheStartOfTheDay() {
        let content = merge([member(roomA, [event("a1", minutes: 30)], reachedStart: true)])
        let dates = content.entries.compactMap { entry -> Date? in
            guard case let .dateDivider(_, date) = entry else { return nil }
            return date
        }
        #expect(dates == [calendar.startOfDay(for: morning)])
    }

    /// 2026-11-10 03:00 UTC is still 2026-11-09 in Chicago (UTC-6).
    @Test func dateDividersFollowTheGivenCalendar() {
        let members = [
            member(roomA, [event("a1", minutes: -360), event("a2", minutes: 0)], reachedStart: true),
        ]
        let utc = render(merge(members, calendar: calendar))
        let chicago = render(merge(members, calendar: zonedCalendar("America/Chicago")))
        #expect(utc == ["start", "day:2026-11-10", "a1", "a2"])
        #expect(chicago == ["start", "day:2026-11-09", "a1", "day:2026-11-10", "a2"])
    }

    /// A local echo from a clock behind the server's can carry an earlier
    /// day than the newest server event. It stays under the current
    /// divider, so no day shows twice.
    @Test func dateDividersNeverGoBackToAnEarlierDay() {
        // 2026-11-09 23:00, 2026-11-10 00:00:30, and an echo at 2026-11-09 23:59:50.
        let content = merge([
            member(roomA, [event("a0", minutes: -600), event("a1", minutes: -539.5)], reachedStart: true),
            member(roomB, [echo("echoB", minutes: -540 - 1.0 / 6)], reachedStart: true),
        ])
        #expect(render(content) == [
            "start", "day:2026-11-09", "note:!a", "a0", "day:2026-11-10", "a1", "note:!b", "echoB",
        ])
    }

    /// The divider is keyed by its day, not by the first item of the day,
    /// so an older item of the same day keeps the divider's identity.
    @Test func dateDividerIdentifierDoesNotDependOnTheFirstItemOfTheDay() {
        let before = merge([member(roomA, [event("a2", minutes: 10)], reachedStart: true)])
        let after = merge([member(roomA, [event("a1", minutes: 5), event("a2", minutes: 10)], reachedStart: true)])
        let dayIds = { (content: MergedTimelineContent<MergeTestItem>) in
            content.entries.filter { render(entry: $0).hasPrefix("day:") }.map(\.id)
        }
        #expect(dayIds(before) == ["merged:day:2026-11-10"])
        #expect(dayIds(after) == dayIds(before))
    }

    // MARK: Identifiers

    /// The SDK's unique identifiers are unique per timeline, so two rooms
    /// can hand the merge the same one.
    @Test func itemIdentifiersAreScopedByRoom() {
        let content = merge([
            member(roomA, [event("1", minutes: 0)], reachedStart: true),
            member(roomB, [event("1", minutes: 5)], reachedStart: true),
        ])
        let itemIds = content.entries.compactMap { entry -> String? in
            guard case let .item(id, _, _) = entry else { return nil }
            return id
        }
        #expect(itemIds == ["merged:item:!a|1", "merged:item:!b|1"])
        #expect(content.entries.compactMap(\.roomId) == [roomA, roomA, roomB, roomB])
    }

    @Test func everyIdentifierIsUniqueAndCarriesThePrefix() {
        let content = merge([
            member(roomA, [
                otherVirtual(), dateDivider(), event("1", minutes: -900), event("2", minutes: 0),
                readMarker(), event("3", minutes: 20), echo("4", minutes: 40),
            ], reachedStart: true),
            member(roomB, [
                dateDivider(), event("1", minutes: -600), event("2", minutes: 10), echo("3", minutes: 30),
            ], reachedStart: true),
            member(roomC, [event("1", minutes: -890), event("2", minutes: 15)], reachedStart: true),
        ])
        let ids = content.entries.map(\.id)
        #expect(TimelineRowIdentity.canInsert(ids) { _ in false })
        #expect(ids.allSatisfy { $0.hasPrefix(MergedTimelineEntryID.prefix) })
        #expect(render(content).filter { $0 == "read" }.count == 1)
    }
}

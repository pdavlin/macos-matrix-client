import Foundation
@testable import Models
import Testing

/// MATRIX-142: the clamp at the oldest end, the pagination targets, and the
/// shape of the merge's cost.
struct MergedTimelinePaginationTests: MergedTimelineFixtures {
    // MARK: Oldest loaded timestamp

    @Test func oldestLoadedTimestampIsTheFirstServerEventByPosition() {
        let member = member(roomA, [
            otherVirtual(), dateDivider(), readMarker(),
            event("a1", minutes: 10), event("a2", minutes: 2), echo("echo", minutes: -60),
        ])
        #expect(member.oldestLoadedTimestamp == date(minutes: 10))
    }

    @Test func oldestLoadedTimestampIsNilWithoutAServerEvent() {
        let member = member(roomA, [dateDivider(), echo("echo", minutes: 0)])
        #expect(member.oldestLoadedTimestamp == nil)
    }

    // MARK: Boundary

    @Test func boundaryIsTheNewestOldestLoadedTimestampOfMembersNotAtTheirStart() {
        let members = [
            member(roomA, [event("a1", minutes: -60)]),
            member(roomB, [event("b1", minutes: -10)]),
            member(roomC, [event("c1", minutes: -30)]),
        ]
        #expect(MergedTimelineMerger.boundary(of: members) == .clamped(at: date(minutes: -10)))
    }

    @Test func membersAtTheirStartDoNotClamp() {
        let members = [
            member(roomA, [event("a1", minutes: -60)]),
            member(roomB, [event("b1", minutes: -10)], reachedStart: true),
        ]
        #expect(MergedTimelineMerger.boundary(of: members) == .clamped(at: date(minutes: -60)))
    }

    @Test func boundaryIsOpenWhenEveryMemberReachedItsStart() {
        let members = [
            member(roomA, [event("a1", minutes: -60)], reachedStart: true),
            member(roomB, [], reachedStart: true),
        ]
        #expect(MergedTimelineMerger.boundary(of: members) == .open)
    }

    @Test func boundaryIsPendingWhileAMemberNotAtItsStartHasLoadedNoEvent() {
        let members = [
            member(roomA, [event("a1", minutes: -60)]),
            member(roomB, [dateDivider()]),
        ]
        #expect(MergedTimelineMerger.boundary(of: members) == .pending)
    }

    @Test func boundaryHidesOnlyServerEventsOlderThanIt() {
        let at = date(minutes: 0)
        #expect(MergedTimelineBoundary.clamped(at: at).hides(serverTimestamp: date(minutes: -1)))
        #expect(!MergedTimelineBoundary.clamped(at: at).hides(serverTimestamp: at))
        #expect(!MergedTimelineBoundary.clamped(at: at).hides(serverTimestamp: date(minutes: 1)))
        #expect(!MergedTimelineBoundary.open.hides(serverTimestamp: date(minutes: -1_000_000)))
        #expect(MergedTimelineBoundary.pending.hides(serverTimestamp: date(minutes: 1_000_000)))
    }

    // MARK: Clamp

    @Test func mergeHidesServerEventsOlderThanTheBoundary() {
        let content = merge([
            member(roomA, [event("a1", minutes: -60), event("a2", minutes: -20), event("a3", minutes: 5)]),
            member(roomB, [event("b1", minutes: -20), event("b2", minutes: 0)]),
        ])
        #expect(content.boundary == .clamped(at: date(minutes: -20)))
        #expect(items(content) == ["a2", "b1", "b2", "a3"])
    }

    @Test func pendingMemberHidesEveryServerEventButNoLocalEcho() {
        let content = merge([
            member(roomA, [event("a1", minutes: 0), echo("echoA", minutes: 1)]),
            member(roomB, []),
        ])
        #expect(content.boundary == .pending)
        #expect(render(content) == ["day:2026-11-10", "echoA"])
    }

    /// Paginating the holder moves the boundary back, and the other room's
    /// older events show in place, with no gap at any step.
    @Test func paginatingTheHolderRevealsTheOtherRoomsOlderEvents() {
        let quietRoom = member(roomB, [event("b1", minutes: -300), event("b2", minutes: -120)])
        let busyRecent = [event("a3", minutes: -60), event("a4", minutes: 0)]
        let first = merge([member(roomA, busyRecent), quietRoom])
        #expect(items(first) == ["a3", "a4"])
        #expect(MergedTimelineMerger.paginationTargets(of: [member(roomA, busyRecent), quietRoom]) == [roomA])

        let paginated = [event("a1", minutes: -400), event("a2", minutes: -200)] + busyRecent
        let second = merge([member(roomA, paginated), quietRoom])
        #expect(second.boundary == .clamped(at: date(minutes: -300)))
        #expect(items(second) == ["b1", "a2", "b2", "a3", "a4"])
        #expect(MergedTimelineMerger.paginationTargets(of: [member(roomA, paginated), quietRoom]) == [roomB])
    }

    // MARK: Pagination targets

    @Test func paginationTargetsAreTheBoundaryHolders() {
        let members = [
            member(roomA, [event("a1", minutes: -60)]),
            member(roomB, [event("b1", minutes: -10)]),
            member(roomC, [event("c1", minutes: -10)]),
        ]
        #expect(MergedTimelineMerger.paginationTargets(of: members) == [roomB, roomC])
    }

    @Test func toleranceAddsMembersCloseToTheBoundary() {
        let members = [
            member(roomA, [event("a1", minutes: -60)]),
            member(roomB, [event("b1", minutes: -10)]),
            member(roomC, [event("c1", minutes: -14)]),
        ]
        #expect(MergedTimelineMerger.paginationTargets(of: members, tolerance: 5 * 60) == [roomB, roomC])
        #expect(MergedTimelineMerger.paginationTargets(of: members, tolerance: 60 * 60) == [roomA, roomB, roomC])
        #expect(MergedTimelineMerger.paginationTargets(of: members, tolerance: -60 * 60) == [roomB])
    }

    @Test func membersAtTheirStartAreNeverTargets() {
        let members = [
            member(roomA, [event("a1", minutes: -10)], reachedStart: true),
            member(roomB, [event("b1", minutes: -60)]),
        ]
        #expect(MergedTimelineMerger.paginationTargets(of: members, tolerance: 24 * 60 * 60) == [roomB])
    }

    @Test func noTargetsWhenTheBoundaryIsOpen() {
        let members = [
            member(roomA, [event("a1", minutes: -10)], reachedStart: true),
            member(roomB, [], reachedStart: true),
        ]
        #expect(MergedTimelineMerger.paginationTargets(of: members).isEmpty)
    }

    @Test func pendingTargetsAreTheMembersWithoutALoadedEvent() {
        let members = [
            member(roomA, [event("a1", minutes: -10)]),
            member(roomB, [dateDivider()]),
            member(roomC, [], reachedStart: true),
        ]
        #expect(MergedTimelineMerger.paginationTargets(of: members) == [roomB])
    }

    // MARK: Cost

    /// Reads each item's kind and counts the reads.
    private final class KindReads {
        var count = 0
    }

    private struct CountingItem: MergedTimelineSourceItem {
        let mergedItemId: String
        let kind: MergedTimelineItemKind
        let reads: KindReads

        var mergedItemKind: MergedTimelineItemKind {
            reads.count += 1
            return kind
        }
    }

    /// `rooms` rooms of `perRoom` events each, interleaved one second apart,
    /// with an SDK date divider every 500 items and one read marker.
    private func largeMembers(rooms: Int, perRoom: Int, reads: KindReads) -> [MergedTimelineMember<CountingItem>] {
        (0 ..< rooms).map { room in
            var items: [CountingItem] = []
            for index in 0 ..< perRoom {
                if index > 0, index.isMultiple(of: 500) {
                    items.append(CountingItem(mergedItemId: "dd\(index)", kind: .dateDivider, reads: reads))
                }
                if room == 1, index == perRoom - 100 {
                    items.append(CountingItem(mergedItemId: "rm", kind: .readMarker, reads: reads))
                }
                let date = morning.addingTimeInterval(TimeInterval(index * rooms + room) * 60)
                items.append(CountingItem(mergedItemId: "\(index)", kind: .event(serverTimestamp: date), reads: reads))
            }
            return MergedTimelineMember(roomId: "!room\(room)", items: items, reachedStart: true)
        }
    }

    /// The merge is linear: at most `k - 1` head comparisons per shown item,
    /// and one kind read per item plus one per member (for its oldest loaded
    /// event). No timing: CI clocks are not reliable.
    @Test func mergeCostIsLinearInTheItemCount() {
        let reads = KindReads()
        let members = largeMembers(rooms: 3, perRoom: 5000, reads: reads)
        let itemCount = members.reduce(0) { $0 + $1.items.count }
        reads.count = 0

        var stats = MergeStats()
        let content = MergedTimelineMerger.merge(members, calendar: calendar, stats: &stats)

        let shown = content.entries.compactMap { entry -> CountingItem? in
            guard case let .item(_, _, item) = entry else { return nil }
            return item
        }
        #expect(shown.count == 15000)
        #expect(stats.keyComparisons <= shown.count * (members.count - 1))
        #expect(reads.count == itemCount + members.count)
        #expect(TimelineRowIdentity.canInsert(content.entries.map(\.id)) { _ in false })

        let dates = shown.compactMap { item -> Date? in
            guard case let .event(date) = item.kind else { return nil }
            return date
        }
        #expect(zip(dates, dates.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func doublingTheItemsAtMostDoublesTheComparisons() {
        let reads = KindReads()
        var small = MergeStats()
        _ = MergedTimelineMerger.merge(largeMembers(rooms: 3, perRoom: 2000, reads: reads), calendar: calendar, stats: &small)
        var large = MergeStats()
        _ = MergedTimelineMerger.merge(largeMembers(rooms: 3, perRoom: 4000, reads: reads), calendar: calendar, stats: &large)
        #expect(small.keyComparisons > 0)
        #expect(large.keyComparisons <= 2 * small.keyComparisons + 10)
    }

    @Test func oneMemberNeedsNoComparison() {
        let reads = KindReads()
        var stats = MergeStats()
        _ = MergedTimelineMerger.merge(largeMembers(rooms: 1, perRoom: 1000, reads: reads), calendar: calendar, stats: &stats)
        #expect(stats.keyComparisons == 0)
    }
}

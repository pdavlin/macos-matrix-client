import Foundation
@testable import Models
import Testing

/// MATRIX-142 Phase B: the cost of one merged-timeline recompute, on the full
/// path that runs without the SDK.
///
/// The path is what `MergedLiveTimeline.recompute()` runs after a coalesced
/// batch: refresh the changed member's item cache (one dictionary lookup per
/// item, keyed by object identity), merge, build and group the rows, remove
/// repeated identifiers, diff against the previous rows, and map the rows
/// for publishing. The FFI read of a new item is not in it: it happens once
/// per item, not once per recompute.
///
/// Run it in a release build for the numbers in the PR:
///
///     swift test --package-path MactrixLibrary -c release \
///         -Xswiftc -enable-testing --filter MergedTimelinePerformanceTests
///
/// The tests print the median time and check only correctness, so a slow
/// debug or CI machine does not fail them.
struct MergedTimelinePerformanceTests: MergedTimelineRowFixtures {
    /// Stands in for the SDK's `TimelineItem` object, whose identity keys
    /// Core's item cache.
    final class SourceObject {}

    /// One synthetic member room: its source objects and the cached items.
    struct Room {
        var roomId: String
        var objects: [SourceObject]
        var cache: [ObjectIdentifier: RowTestItem]
    }

    /// How the rooms' messages interleave.
    enum Layout: String, CaseIterable {
        /// Each room writes 20 messages in a row, then the next room: the
        /// usual shape of a merged chat.
        case runs
        /// The rooms take turns on every message: the worst case, a source
        /// note above every message.
        case alternating
    }

    /// Three rooms of `count` messages each, one minute apart, with two
    /// senders, plus the SDK's read marker near the newest end. The newest
    /// message is room C's, at minute `3 × count − 1`, in both layouts.
    private func rooms(count: Int, layout: Layout) -> [Room] {
        [roomA, roomB, roomC].enumerated().map { offset, roomId in
            var objects: [SourceObject] = []
            var cache: [ObjectIdentifier: RowTestItem] = [:]
            for index in 0 ..< count {
                let object = SourceObject()
                let minutes = switch layout {
                case .runs: Double((index / 20) * 60 + offset * 20 + index % 20)
                case .alternating: Double(index * 3 + offset)
                }
                let item: RowTestItem = if index == count - 5 {
                    sdkReadMarker("rm")
                } else {
                    message("\(roomId)-\(index)", in: roomId, from: index % 4 == 0 ? ada : bob, minutes: minutes)
                }
                objects.append(object)
                cache[ObjectIdentifier(object)] = item
            }
            return Room(roomId: roomId, objects: objects, cache: cache)
        }
    }

    /// What one recompute publishes.
    struct Recompute {
        var rows: [MergedDisplayRow]
        var updates: [TimelineRowDisplayUpdate]
        var published: [TimelineRow]
    }

    /// One recompute on the full path. Only the first room's cache is
    /// refreshed, as after a diff in that room.
    private func recompute(_ rooms: [Room], previous: [MergedDisplayRow]) -> Recompute {
        var members: [MergedTimelineMember<RowTestItem>] = []
        for (offset, room) in rooms.enumerated() {
            var items: [RowTestItem] = []
            items.reserveCapacity(room.objects.count)
            if offset == 0 {
                var fresh: [ObjectIdentifier: RowTestItem] = [:]
                fresh.reserveCapacity(room.objects.count)
                for object in room.objects {
                    let key = ObjectIdentifier(object)
                    guard let item = room.cache[key] else { continue }
                    fresh[key] = item
                    items.append(item)
                }
            } else {
                items = room.objects.compactMap { room.cache[ObjectIdentifier($0)] }
            }
            members.append(MergedTimelineMember(roomId: room.roomId, items: items, reachedStart: false))
        }
        let content = MergedTimelineMerger.merge(members, calendar: calendar)
        var labels: [String: MergedSourceLabel] = [:]
        for room in rooms {
            labels[room.roomId] = MergedSourceLabel(roomId: room.roomId, network: .slack, roomName: room.roomId)
        }
        let built = MergedTimelineRowBuilder.displayRows(from: content, labels: labels, calendar: calendar)
        let unique = TimelineRowIdentity.removingDuplicates(built) { (row: MergedDisplayRow) -> String in row.id }.unique
        let updates = MergedTimelineRowBuilder.updates(from: previous, to: unique)
        _ = MergedTimelineMerger.paginationTargets(of: members)
        return Recompute(rows: unique, updates: updates, published: unique.map(\.row))
    }

    private func medianMilliseconds(runs: Int, _ body: () -> Void) -> Double {
        let clock = ContinuousClock()
        var samples: [Double] = []
        for _ in 0 ..< runs {
            let elapsed = clock.measure(body).components
            samples.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        }
        return samples.sorted()[samples.count / 2]
    }

    @Test(arguments: [300, 5000], Layout.allCases)
    func recomputeCost(itemsPerRoom: Int, layout: Layout) {
        var rooms = rooms(count: itemsPerRoom, layout: layout)
        let first = recompute(rooms, previous: [])
        #expect(first.updates.map(\.change) == [.reset])
        let runs = itemsPerRoom > 1000 ? 9 : 31

        // A recompute that changes nothing: the cost of a batch that only
        // touched what the merge does not show.
        var unchanged: [TimelineRowDisplayUpdate] = []
        let idle = medianMilliseconds(runs: runs) {
            unchanged = recompute(rooms, previous: first.rows).updates
        }
        #expect(unchanged.isEmpty)

        // One new message at the newest end of room A.
        let arrival = SourceObject()
        rooms[0].objects.append(arrival)
        // Just after room C's newest message, on the same day.
        rooms[0].cache[ObjectIdentifier(arrival)] = message("new", in: roomA, from: bob, minutes: Double(itemsPerRoom * 3) - 0.5)
        var appended: [TimelineRowDisplayUpdate] = []
        let append = medianMilliseconds(runs: runs) {
            appended = recompute(rooms, previous: first.rows).updates
        }
        // The new message, and its source note, at the newest end.
        #expect(appended.map(\.change) == [.insert(index: 0, count: 2)])

        // A full rebuild from no rows (the first load).
        let cold = medianMilliseconds(runs: runs) {
            _ = recompute(rooms, previous: [])
        }

        print(
            """
            MergedTimelinePerformance 3 x \(itemsPerRoom) \(layout.rawValue): \(first.rows.count) rows; \
            unchanged \(String(format: "%.3f", idle)) ms, \
            one arrival \(String(format: "%.3f", append)) ms, \
            first load \(String(format: "%.3f", cold)) ms (median)
            """
        )
    }
}

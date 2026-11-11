import Foundation
@testable import Models
import Testing

/// MATRIX-142 Phase B: the identifier diff that turns one merged row array
/// into the next as container changes.
struct TimelineRowDiffTests {
    /// A row stand-in: an identifier and a content version.
    struct Cell: Equatable {
        var id: String
        var content = 0
    }

    private func cells(_ ids: String...) -> [Cell] {
        ids.map { Cell(id: $0) }
    }

    private func changes(_ old: [Cell], _ new: [Cell]) -> [TimelineDisplayChange] {
        TimelineRowDiff.changes(from: old, to: new, id: \.id, hasSameContent: ==)
    }

    /// Replays changes the way the container does: in order, each against
    /// the array the previous one left, with inserted and updated content
    /// read from `new` at the change's index.
    private func replay(_ changes: [TimelineDisplayChange], on old: [Cell], new: [Cell]) -> [Cell] {
        var rows = old
        for change in changes {
            switch change {
            case .reset:
                rows = new
            case let .remove(index, count):
                rows.removeSubrange(index ..< index + count)
            case let .insert(index, count):
                rows.insert(contentsOf: new[index ..< index + count], at: index)
            case let .update(index):
                #expect(rows[index].id == new[index].id, "an update must keep the row's identity")
                rows[index] = new[index]
            }
        }
        return rows
    }

    // MARK: - Shapes

    @Test
    func nothingChangedIsNoChange() {
        #expect(changes(cells("a", "b"), cells("a", "b")).isEmpty)
        #expect(changes([], []).isEmpty)
    }

    @Test
    func theFirstRowsAndAFullReplacementAreAReset() {
        #expect(changes([], cells("a")) == [.reset])
        #expect(changes(cells("a", "b"), cells("c", "d")) == [.reset])
        #expect(changes(cells("a"), []) == [.reset])
    }

    @Test
    func aRepeatedIdentifierInTheOldRowsIsAReset() {
        #expect(changes(cells("a", "a"), cells("a")) == [.reset])
    }

    @Test
    func newRowsAtTheNewestEndAreOneInsertAtZero() {
        #expect(changes(cells("c", "b", "a"), cells("e", "d", "c", "b", "a")) == [.insert(index: 0, count: 2)])
    }

    @Test
    func aPaginationBatchIsOneInsertAtTheOldestEnd() {
        let old = cells("c", "b", "a")
        let new = old + (0 ..< 100).map { Cell(id: "old\($0)") }

        #expect(changes(old, new) == [.insert(index: 3, count: 100)])
    }

    @Test
    func removalsComeFirstHighestIndexDownAndMerge() {
        let result = changes(cells("a", "b", "c", "d", "e", "f"), cells("a", "d", "f"))

        #expect(result == [.remove(index: 4, count: 1), .remove(index: 1, count: 2)])
    }

    @Test
    func aMovedRowIsRemovedAndInsertedAgain() {
        // Older rows of the same day appear under the day divider: an insert,
        // because the divider keeps its order relative to the other rows.
        #expect(changes(cells("m2", "m1", "day"), cells("m2", "m1", "x1", "day")) == [.insert(index: 2, count: 1)])

        let moved = changes(cells("a", "b", "c"), cells("c", "a", "b"))
        #expect(moved == [.remove(index: 2, count: 1), .insert(index: 0, count: 1)])
    }

    @Test
    func aChangedRowThatStaysIsAnUpdateAtItsNewIndex() {
        let old = cells("b", "a")
        let new = [Cell(id: "c"), Cell(id: "b", content: 1), Cell(id: "a")]

        #expect(changes(old, new) == [.insert(index: 0, count: 1), .update(index: 1)])
    }

    @Test
    func updatesCarryTheirRowsFromTheNewArray() {
        let old = [MergedDisplayRow(row: .virtual(uniqueId: "b", item: .readMarker))]
        let new = [
            MergedDisplayRow(row: .virtual(uniqueId: "c", item: .timelineStart)),
            MergedDisplayRow(row: .virtual(uniqueId: "b", item: .readMarker)),
        ]
        let updates = MergedTimelineRowBuilder.updates(from: old, to: new)

        #expect(updates.map(\.change) == [.insert(index: 0, count: 1)])
        #expect(updates.first?.rows.map(\.uniqueId) == ["c"])
    }

    // MARK: - Replay

    @Test(arguments: 0 ..< 200)
    func replayingTheChangesGivesTheNewRows(seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed))
        let old = (0 ..< Int.random(in: 0 ... 40, using: &generator)).map { Cell(id: "r\($0)") }
        var new = old
        var nextId = old.count

        for _ in 0 ..< Int.random(in: 0 ... 8, using: &generator) {
            switch Int.random(in: 0 ..< 4, using: &generator) {
            case 0:
                let at = Int.random(in: 0 ... new.count, using: &generator)
                let count = Int.random(in: 1 ... 5, using: &generator)
                new.insert(contentsOf: (0 ..< count).map { Cell(id: "r\(nextId + $0)") }, at: at)
                nextId += count
            case 1 where !new.isEmpty:
                new.remove(at: Int.random(in: 0 ..< new.count, using: &generator))
            case 2 where new.count > 1:
                let from = Int.random(in: 0 ..< new.count, using: &generator)
                let cell = new.remove(at: from)
                new.insert(cell, at: Int.random(in: 0 ... new.count, using: &generator))
            case 3 where !new.isEmpty:
                new[Int.random(in: 0 ..< new.count, using: &generator)].content += 1
            default:
                break
            }
        }

        let result = changes(old, new)
        #expect(replay(result, on: old, new: new) == new)
        // Every change is in range, and a structural batch never repeats an
        // identifier while it applies (MATRIX-130).
        if !result.contains(.reset) {
            var rows = old
            for change in result {
                switch change {
                case let .remove(index, count):
                    #expect(index >= 0 && index + count <= rows.count)
                    rows.removeSubrange(index ..< index + count)
                case let .insert(index, count):
                    #expect(index >= 0 && index <= rows.count)
                    rows.insert(contentsOf: new[index ..< index + count], at: index)
                    #expect(Set(rows.map(\.id)).count == rows.count)
                case let .update(index):
                    #expect(rows.indices.contains(index))
                case .reset:
                    break
                }
            }
        }
    }

    // MARK: - Longest increasing subsequence

    @Test
    func theKeptRowsAreALongestIncreasingRun() {
        #expect(TimelineRowDiff.longestIncreasingSubsequenceMask([]) == [])
        #expect(TimelineRowDiff.longestIncreasingSubsequenceMask([0, 1, 2]) == [true, true, true])
        #expect(TimelineRowDiff.longestIncreasingSubsequenceMask([2, 0, 1]) == [false, true, true])
        let mask = TimelineRowDiff.longestIncreasingSubsequenceMask([3, 0, 4, 1, 5, 2, 6])
        #expect(mask.filter(\.self).count == 4)
        let kept = zip([3, 0, 4, 1, 5, 2, 6], mask).filter(\.1).map(\.0)
        #expect(kept == kept.sorted())
    }
}

/// A small seeded generator, so a failing case can be replayed.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

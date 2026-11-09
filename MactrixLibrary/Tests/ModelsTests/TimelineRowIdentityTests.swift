import Foundation
@testable import Models
import Testing

/// MATRIX-130: the identifier checks that keep the timeline snapshot from
/// raising an Objective-C exception inside SwiftUI's view update.
struct TimelineRowIdentityTests {
    @Test
    func insertOfNewUniqueIdsIsAllowed() {
        let existing: Set = ["a", "b"]
        #expect(TimelineRowIdentity.canInsert(["c", "d"], isPresent: existing.contains))
    }

    @Test
    func emptyInsertIsAllowed() {
        #expect(TimelineRowIdentity.canInsert([], isPresent: { _ in true }))
    }

    /// The crash case: the SDK diff names a row the snapshot already holds.
    @Test
    func insertOfAnExistingIdIsRefused() {
        let existing: Set = ["a", "b"]
        #expect(!TimelineRowIdentity.canInsert(["c", "b"], isPresent: existing.contains))
    }

    @Test
    func insertWithARepeatedIdIsRefused() {
        #expect(!TimelineRowIdentity.canInsert(["c", "d", "c"], isPresent: { _ in false }))
    }

    @Test
    func removingDuplicatesKeepsTheFirstOccurrenceInOrder() {
        let rows = ["new", "mid", "new", "old", "mid"]
        let result = TimelineRowIdentity.removingDuplicates(rows, id: { $0 })
        #expect(result.unique == ["new", "mid", "old"])
        #expect(result.removedIds == ["new", "mid"])
    }

    @Test
    func removingDuplicatesLeavesUniqueRowsUntouched() {
        let rows = ["a", "b", "c"]
        let result = TimelineRowIdentity.removingDuplicates(rows, id: { $0 })
        #expect(result.unique == rows)
        #expect(result.removedIds.isEmpty)
    }
}

/// MATRIX-130: a queued reset covers every later change, because the
/// container rebuilds from the final display order.
struct TimelineDisplayChangeQueueTests {
    private func enqueue(_ changes: [TimelineDisplayChange]) -> [TimelineDisplayChange] {
        var queue: [TimelineDisplayChange] = []
        for change in changes {
            TimelineDisplayChangeQueue.enqueue(change, into: &queue) { (queued: TimelineDisplayChange) -> TimelineDisplayChange in
                queued
            }
        }
        return queue
    }

    @Test
    func changesWithoutAResetQueueInOrder() {
        let changes: [TimelineDisplayChange] = [.insert(index: 0, count: 2), .update(index: 1), .remove(index: 0, count: 1)]
        #expect(enqueue(changes) == changes)
    }

    @Test
    func aResetReplacesEverythingQueuedBeforeIt() {
        #expect(enqueue([.insert(index: 0, count: 2), .update(index: 1), .reset]) == [.reset])
    }

    /// The crash case: the SDK clears the timeline and appends to it between
    /// two view updates. The rebuild already shows the appended rows.
    @Test
    func aChangeAfterAQueuedResetIsDropped() {
        #expect(enqueue([.reset, .insert(index: 0, count: 3), .update(index: 0), .remove(index: 1, count: 1)]) == [.reset])
    }

    @Test
    func aSecondResetStaysASingleReset() {
        #expect(enqueue([.reset, .insert(index: 0, count: 1), .reset]) == [.reset])
    }
}

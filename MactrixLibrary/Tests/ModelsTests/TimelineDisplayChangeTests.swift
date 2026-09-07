import Foundation
@testable import Models
import Testing

/// S-34: the index math that mirrors the SDK's oldest-first timeline onto the
/// newest-first array the container renders.
///
/// The mirror is the reason an update costs the size of the diff instead of
/// the length of the timeline, so the arithmetic is tested directly rather
/// than through the container.
struct TimelineDisplayOrderTests {
    @Test
    func displayIndexReversesTheArray() {
        // SDK order [oldest, mid, newest] displays as [newest, mid, oldest].
        #expect(TimelineDisplayOrder.displayIndex(ofSdkIndex: 0, count: 3) == 2)
        #expect(TimelineDisplayOrder.displayIndex(ofSdkIndex: 1, count: 3) == 1)
        #expect(TimelineDisplayOrder.displayIndex(ofSdkIndex: 2, count: 3) == 0)
    }

    @Test
    func displayIndexRoundTrips() {
        let count = 7
        for sdkIndex in 0 ..< count {
            let display = TimelineDisplayOrder.displayIndex(ofSdkIndex: sdkIndex, count: count)
            #expect(TimelineDisplayOrder.displayIndex(ofSdkIndex: display, count: count) == sdkIndex)
        }
    }

    /// An insert grows the array, so its display position is one further out
    /// than an existing element at the same SDK index would sit.
    @Test
    func insertIndexAccountsForTheGrownArray() {
        // Inserting at the oldest end of a 3-element array appends in display order.
        #expect(TimelineDisplayOrder.displayInsertIndex(ofSdkIndex: 0, countBeforeInsert: 3) == 3)
        // Inserting at the newest end prepends.
        #expect(TimelineDisplayOrder.displayInsertIndex(ofSdkIndex: 3, countBeforeInsert: 3) == 0)
        #expect(TimelineDisplayOrder.displayInsertIndex(ofSdkIndex: 0, countBeforeInsert: 0) == 0)
    }

    /// Mirrors a sequence of SDK mutations onto both orders and checks the
    /// display array stays the exact reverse of the SDK array.
    @Test
    func mirroredMutationsKeepBothOrdersInStep() {
        var sdk = ["a", "b", "c"]
        var display = ["c", "b", "a"]

        // Insert at SDK index 1.
        let insertAt = TimelineDisplayOrder.displayInsertIndex(ofSdkIndex: 1, countBeforeInsert: display.count)
        sdk.insert("x", at: 1)
        display.insert("x", at: insertAt)
        #expect(display == sdk.reversed())

        // Replace at SDK index 2.
        let setAt = TimelineDisplayOrder.displayIndex(ofSdkIndex: 2, count: display.count)
        sdk[2] = "y"
        display[setAt] = "y"
        #expect(display == sdk.reversed())

        // Remove at SDK index 0.
        let removeAt = TimelineDisplayOrder.displayIndex(ofSdkIndex: 0, count: display.count)
        sdk.remove(at: 0)
        display.remove(at: removeAt)
        #expect(display == sdk.reversed())
    }

    /// The SDK keeps the oldest `length` items on a truncate, so the removal
    /// lands at the front of the display order.
    @Test
    func truncateRemovesFromTheNewestEnd() {
        let sdk = ["a", "b", "c", "d"]
        var display = ["d", "c", "b", "a"]

        let removed = sdk.count - 2
        display.removeFirst(removed)

        #expect(display == Array(sdk.prefix(2).reversed()))
    }

    @Test
    func indexValidationRejectsOutOfRange() {
        #expect(TimelineDisplayOrder.isValidIndex(0, count: 1))
        #expect(!TimelineDisplayOrder.isValidIndex(1, count: 1))
        #expect(!TimelineDisplayOrder.isValidIndex(-1, count: 1))

        #expect(TimelineDisplayOrder.isValidInsertIndex(1, count: 1))
        #expect(!TimelineDisplayOrder.isValidInsertIndex(2, count: 1))
        #expect(TimelineDisplayOrder.isValidInsertIndex(0, count: 0))
    }
}

struct TimelineDisplayChangeTests {
    @Test
    func onlyContentUpdatesAreNonStructural() {
        #expect(!TimelineDisplayChange.update(index: 3).isStructural)
        #expect(TimelineDisplayChange.insert(index: 0, count: 2).isStructural)
        #expect(TimelineDisplayChange.remove(index: 0, count: 2).isStructural)
        #expect(TimelineDisplayChange.reset.isStructural)
    }

    /// The per-update cost the acceptance criteria track: a batch reports the
    /// rows it touched, not the rows in the timeline.
    @Test
    func rowCountReportsTouchedRows() {
        let batch: [TimelineDisplayChange] = [
            .insert(index: 0, count: 3),
            .update(index: 5),
            .remove(index: 9, count: 2),
        ]

        #expect(batch.reduce(0) { $0 + $1.rowCount } == 6)
        #expect(TimelineDisplayChange.reset.rowCount == 0)
    }
}

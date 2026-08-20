import Foundation
import Testing
@testable import TimelineSpikeCore

@Suite("Visible range")
@MainActor
struct VisibleRangeTests {
    private func store(count: Int = 200) -> TimelineStore {
        TimelineStore(seed: 77, initialEventCount: count)
    }

    @Test("A contiguous run of identifiers maps to its item-index range")
    func contiguousRun() {
        let store = store()
        let ids = (40 ... 49).map(EventID.init)
        #expect(store.visibleRange(spanning: ids) == 40 ..< 50)
    }

    @Test("Only the extremes matter, so the input need not be sorted")
    func orderDoesNotMatter() {
        let store = store()
        let ids = [EventID(49), EventID(41), EventID(45), EventID(40)]
        #expect(store.visibleRange(spanning: ids) == 40 ..< 50)
    }

    @Test("A single identifier spans one item")
    func singleIdentifier() {
        let store = store()
        #expect(store.visibleRange(spanning: [EventID(12)]) == 12 ..< 13)
    }

    @Test("An empty visible set has no range")
    func emptyInput() {
        let store = store()
        #expect(store.visibleRange(spanning: []) == nil)
    }

    @Test("Identifiers outside the loaded window are skipped, not counted")
    func unloadedIdentifiersAreSkipped() {
        let store = store()
        // -1 is older than the window and 500 is newer; both must be ignored rather than
        // widening the range or returning nil.
        let ids = [EventID(-1), EventID(30), EventID(35), EventID(500)]
        #expect(store.visibleRange(spanning: ids) == 30 ..< 36)
    }

    @Test("A visible set with nothing loaded has no range")
    func nothingLoaded() {
        let store = store()
        #expect(store.visibleRange(spanning: [EventID(-10), EventID(9_000)]) == nil)
    }

    @Test("After a prepend the same identifiers map to shifted indices")
    func prependShiftsTheRange() {
        let store = store()
        let ids = (40 ... 49).map(EventID.init)
        #expect(store.visibleRange(spanning: ids) == 40 ..< 50)

        store.prepend(count: 50)
        // The events did not move on the generator index line; their array positions did.
        // A renderer that reported a stale range would make the mutation driver aim at the
        // wrong rows, so this is the invariant the drift measurement rests on.
        #expect(store.visibleRange(spanning: ids) == 90 ..< 100)
        #expect(store.oldestIndex == -50)
    }

    @Test("Negative identifiers resolve once back-pagination has loaded them")
    func negativeIdentifiersResolveAfterPrepend() {
        let store = store()
        #expect(store.visibleRange(spanning: [EventID(-5)]) == nil)
        store.prepend(count: 50)
        #expect(store.visibleRange(spanning: [EventID(-5)]) == 45 ..< 46)
    }

    @Test("The range agrees with itemIndex for every loaded identifier")
    func agreesWithItemIndex() {
        let store = store(count: 60)
        for item in store.items {
            let index = store.itemIndex(for: item.id)
            #expect(store.visibleRange(spanning: [item.id]) == index.map { $0 ..< ($0 + 1) })
        }
    }
}

import Models
import Testing

/// The pacing queue behind MATRIX-57. Identity, coalescing and ordering are
/// the properties the container depends on; the payload is opaque to it.
struct TimelineRowUpdateQueueTests {
    /// Every row is offscreen unless a test says otherwise.
    private func offscreen(_: Int) -> Bool {
        false
    }

    /// Identity resolves to a fixed table, the way the snapshot resolves it.
    private func resolver(_ table: [String: Int]) -> (String) -> Int? {
        { table[$0] }
    }

    @Test
    func repeatedUpdatesToOneRowCollapseToTheNewest() {
        var queue = TimelineRowUpdateQueue<String>()
        queue.enqueue(uniqueId: "a", payload: "first")
        queue.enqueue(uniqueId: "a", payload: "second")
        queue.enqueue(uniqueId: "a", payload: "third")

        #expect(queue.count == 1)

        let taken = queue.take(limit: 10, resolve: resolver(["a": 0]), isVisible: offscreen)
        #expect(taken.map(\.payload) == ["third"])
        #expect(queue.isEmpty)
    }

    /// A row that mutates on every tick must not jump the rows queued behind
    /// it, or a busy row starves the rest under a sustained storm.
    @Test
    func coalescingKeepsTheOriginalPosition() {
        var queue = TimelineRowUpdateQueue<String>()
        queue.enqueue(uniqueId: "a", payload: "a1")
        queue.enqueue(uniqueId: "b", payload: "b1")
        queue.enqueue(uniqueId: "c", payload: "c1")
        queue.enqueue(uniqueId: "a", payload: "a2")

        let taken = queue.take(limit: 10, resolve: resolver(["a": 0, "b": 1, "c": 2]), isVisible: offscreen)
        #expect(taken.map(\.uniqueId) == ["a", "b", "c"])
        #expect(taken.map(\.payload) == ["a2", "b1", "c1"])
    }

    /// The reason entries hold identity: a structural change between the
    /// enqueue and the drain renumbers the rows, and the queued index would
    /// address a different row.
    @Test
    func identityResolvesAgainstTheIndicesAtDrainTime() {
        var queue = TimelineRowUpdateQueue<String>()
        queue.enqueue(uniqueId: "a", payload: "a1")
        queue.enqueue(uniqueId: "b", payload: "b1")

        // Two rows were inserted ahead of both entries since they were queued.
        let taken = queue.take(limit: 10, resolve: resolver(["a": 2, "b": 3]), isVisible: offscreen)
        #expect(taken.map(\.index) == [2, 3])
    }

    /// A row removed by an interleaved structural change no longer resolves.
    /// Its update is dropped, not applied to whichever row took its index.
    @Test
    func unresolvableEntriesAreDroppedRatherThanApplied() {
        var queue = TimelineRowUpdateQueue<String>()
        queue.enqueue(uniqueId: "gone", payload: "g1")
        queue.enqueue(uniqueId: "kept", payload: "k1")

        let taken = queue.take(limit: 10, resolve: resolver(["kept": 4]), isVisible: offscreen)
        #expect(taken.map(\.uniqueId) == ["kept"])
        #expect(queue.isEmpty)
    }

    /// The frame budget: a drain takes a slice and leaves the rest queued.
    @Test
    func takeStopsAtTheLimitAndLeavesTheRemainder() {
        var queue = TimelineRowUpdateQueue<String>()
        let table = ["a": 0, "b": 1, "c": 2, "d": 3]
        for id in ["a", "b", "c", "d"] {
            queue.enqueue(uniqueId: id, payload: id)
        }

        let first = queue.take(limit: 2, resolve: resolver(table), isVisible: offscreen)
        #expect(first.map(\.uniqueId) == ["a", "b"])
        #expect(queue.count == 2)

        let second = queue.take(limit: 2, resolve: resolver(table), isVisible: offscreen)
        #expect(second.map(\.uniqueId) == ["c", "d"])
        #expect(queue.isEmpty)
    }

    @Test
    func takeReturnsNothingForANonPositiveLimit() {
        var queue = TimelineRowUpdateQueue<String>()
        queue.enqueue(uniqueId: "a", payload: "a1")

        #expect(queue.take(limit: 0, resolve: resolver(["a": 0]), isVisible: offscreen).isEmpty)
        #expect(queue.count == 1)
    }

    /// Perceived latency is what the budget buys, so the rows the reader can
    /// see are redrawn before the rows nobody can see.
    @Test
    func visibleRowsAreTakenBeforeOffscreenRows() {
        var queue = TimelineRowUpdateQueue<String>()
        let table = ["far": 0, "near": 1, "alsoFar": 2, "alsoNear": 3]
        for id in ["far", "near", "alsoFar", "alsoNear"] {
            queue.enqueue(uniqueId: id, payload: id)
        }

        let visibleRows = Set([1, 3])
        let taken = queue.take(
            limit: 10,
            resolve: resolver(table),
            isVisible: { visibleRows.contains($0) }
        )

        #expect(taken.map(\.uniqueId) == ["near", "alsoNear", "far", "alsoFar"])
        #expect(taken.map(\.isVisible) == [true, true, false, false])
    }

    /// Visible-first applies to the slice as well: a budget that admits two
    /// rows spends both on rows the reader can see.
    @Test
    func theBudgetIsSpentOnVisibleRowsFirst() {
        var queue = TimelineRowUpdateQueue<String>()
        let table = ["far": 0, "near": 1, "alsoNear": 2]
        for id in ["far", "near", "alsoNear"] {
            queue.enqueue(uniqueId: id, payload: id)
        }

        let taken = queue.take(limit: 2, resolve: resolver(table), isVisible: { $0 > 0 })
        #expect(taken.map(\.uniqueId) == ["near", "alsoNear"])
        #expect(queue.count == 1)
    }

    /// A removed row's identity can come back — a re-insert after a resync —
    /// and the returning row must not inherit the old payload.
    @Test
    func removeDropsQueuedUpdatesByIdentity() {
        var queue = TimelineRowUpdateQueue<String>()
        queue.enqueue(uniqueId: "a", payload: "a1")
        queue.enqueue(uniqueId: "b", payload: "b1")
        queue.enqueue(uniqueId: "c", payload: "c1")

        queue.remove(uniqueIds: ["a", "c"])
        #expect(queue.count == 1)

        let taken = queue.take(limit: 10, resolve: resolver(["a": 0, "b": 1, "c": 2]), isVisible: offscreen)
        #expect(taken.map(\.uniqueId) == ["b"])
    }

    /// A reset rebuilds every row from the source of truth, so anything queued
    /// against the old rows is already applied there.
    @Test
    func removeAllEmptiesTheQueue() {
        var queue = TimelineRowUpdateQueue<String>()
        queue.enqueue(uniqueId: "a", payload: "a1")
        queue.enqueue(uniqueId: "b", payload: "b1")

        queue.removeAll()
        #expect(queue.isEmpty)

        // Re-enqueuing after a clear starts a fresh order.
        queue.enqueue(uniqueId: "b", payload: "b2")
        queue.enqueue(uniqueId: "a", payload: "a2")
        let taken = queue.take(limit: 10, resolve: resolver(["a": 0, "b": 1]), isVisible: offscreen)
        #expect(taken.map(\.uniqueId) == ["b", "a"])
    }
}

import Foundation
import Testing
@testable import TimelineSpikeCore

@Suite("Mutation driver invariants")
@MainActor
struct MutationDriverTests {
    private let seed: UInt64 = 0x0F0F_1E1E_2D2D_3C3C

    private func makeStore(count: Int = 600) -> TimelineStore {
        TimelineStore(seed: seed, initialEventCount: count)
    }

    @Test("Mutation never inserts, removes or reorders events")
    func structureIsPreserved() {
        let store = makeStore()
        let before = store.items.map(\.event)
        let driver = MutationDriver(
            seed: seed,
            configuration: MutationDriverConfiguration(mutationsPerTick: 8)
        )
        for _ in 0 ..< 200 {
            driver.step(store: store, visibleRange: 100 ..< 140)
        }

        let after = store.items.map(\.event)
        #expect(after.count == before.count)
        #expect(after.map(\.id) == before.map(\.id))
        #expect(after.map(\.timestamp) == before.map(\.timestamp))
        #expect(after.map(\.sender) == before.map(\.sender))
        #expect(store.appliedMutationCount > 0)
        #expect(after != before, "the driver must actually change something")
    }

    @Test("Content kind never changes: text stays text, images stay images")
    func contentKindIsStable() {
        let store = makeStore()
        let kindsBefore = store.items.map(\.event.content.isText)
        let driver = MutationDriver(seed: seed)
        for _ in 0 ..< 150 {
            driver.step(store: store, visibleRange: 0 ..< 60)
        }
        #expect(store.items.map(\.event.content.isText) == kindsBefore)
    }

    @Test("Every tick touches both an on-screen and an off-screen item")
    func everyTickCoversBothSides() {
        let store = makeStore()
        let visible = 220 ..< 260
        let driver = MutationDriver(
            seed: seed,
            configuration: MutationDriverConfiguration(mutationsPerTick: 4, onScreenBias: 0.5)
        )

        for _ in 0 ..< 120 {
            let batch = driver.step(store: store, visibleRange: visible)
            #expect(batch.count == 4, "no mutation slot may be dropped for a loaded target")
            let indices = batch.compactMap { store.itemIndex(for: $0.target) }
            #expect(indices.contains { visible.contains($0) }, "a visible item must be touched")
            #expect(indices.contains { !visible.contains($0) }, "an off-screen item must be touched")
        }
    }

    @Test("Off-screen targets are drawn from the whole complement, both sides of the viewport")
    func offScreenTargetsCoverBothSides() {
        let store = makeStore()
        let visible = 250 ..< 290
        let driver = MutationDriver(
            seed: seed,
            configuration: MutationDriverConfiguration(mutationsPerTick: 6, onScreenBias: 0.0)
        )

        var above = false
        var below = false
        for _ in 0 ..< 200 {
            for mutation in driver.step(store: store, visibleRange: visible) {
                guard let index = store.itemIndex(for: mutation.target) else { continue }
                if index < visible.lowerBound { above = true }
                if index >= visible.upperBound { below = true }
            }
        }
        #expect(above)
        #expect(below)
    }

    @Test("With no reported viewport the driver still mutates")
    func worksWithoutAViewport() {
        let store = makeStore()
        let driver = MutationDriver(seed: seed)
        let batch = driver.step(store: store, visibleRange: nil)
        #expect(!batch.isEmpty)
    }

    @Test("An out-of-bounds viewport is clamped rather than trapping")
    func viewportIsClamped() {
        let store = makeStore(count: 80)
        let driver = MutationDriver(seed: seed)
        let batch = driver.step(store: store, visibleRange: -40 ..< 5_000)
        #expect(!batch.isEmpty)
        for mutation in batch {
            #expect(store.itemIndex(for: mutation.target) != nil)
        }
    }

    @Test("Every emitted edit changes the target's height")
    func editsAlwaysChangeLineCount() {
        let store = makeStore()
        let driver = MutationDriver(
            seed: seed,
            configuration: MutationDriverConfiguration(mutationsPerTick: 10, editShare: 1.0)
        )

        var edits = 0
        for _ in 0 ..< 120 {
            let visible = 40 ..< 90
            // One tick can hit the same event twice, so the expected line count is tracked
            // as the batch is walked rather than snapshotted before it.
            var expected: [EventID: Int] = [:]
            for item in store.items {
                if let body = item.event.content.textBody {
                    expected[item.id] = body.lineCount
                }
            }
            var touched: Set<EventID> = []
            for mutation in driver.step(store: store, visibleRange: visible) {
                guard case .editText(let id, let body) = mutation else { continue }
                edits += 1
                guard let old = expected[id] else {
                    Issue.record("an edit targeted a non-text event")
                    continue
                }
                #expect(body.lineCount != old, "every edit must change the rendered height")
                #expect(body.lineCount >= 1)
                #expect(body.lineCount <= SyntheticEventGenerator.maximumLineCount)
                expected[id] = body.lineCount
                touched.insert(id)
            }
            for id in touched {
                #expect(store.event(with: id)?.content.textBody?.lineCount == expected[id])
            }
        }
        #expect(edits > 100)
    }

    @Test("Reaction tallies stay positive and keys stay unique")
    func reactionsStayWellFormed() {
        let store = makeStore()
        let driver = MutationDriver(
            seed: seed,
            configuration: MutationDriverConfiguration(mutationsPerTick: 12, editShare: 0.0)
        )
        var sawRemoval = false
        for _ in 0 ..< 400 {
            for mutation in driver.step(store: store, visibleRange: 10 ..< 50) {
                if case .removeReaction = mutation { sawRemoval = true }
            }
        }
        #expect(sawRemoval, "the driver must exercise reaction removal, not only addition")

        for item in store.items {
            let keys = item.event.reactions.map(\.key)
            #expect(Set(keys).count == keys.count, "no duplicate reaction keys")
            for reaction in item.event.reactions {
                #expect(reaction.count >= 1, "a listed reaction must have a positive tally")
            }
        }
    }

    @Test("Reaction rows both appear and disappear")
    func reactionRowsAppearAndDisappear() {
        let store = makeStore(count: 200)
        let driver = MutationDriver(
            seed: seed,
            configuration: MutationDriverConfiguration(mutationsPerTick: 8, editShare: 0.0)
        )
        var appeared = false
        var disappeared = false
        for _ in 0 ..< 500 {
            var before: [EventID: Bool] = [:]
            for item in store.items {
                before[item.id] = !item.event.reactions.isEmpty
            }
            for mutation in driver.step(store: store, visibleRange: 0 ..< 40) {
                guard let had = before[mutation.target],
                      let now = store.event(with: mutation.target)
                          .map({ !$0.reactions.isEmpty }) else { continue }
                if !had, now { appeared = true }
                if had, !now { disappeared = true }
            }
            if appeared, disappeared { break }
        }
        #expect(appeared)
        #expect(disappeared)
    }

    @Test("The same seed replays the same mutation sequence")
    func mutationStreamIsDeterministic() {
        func run() -> [Mutation] {
            let store = makeStore()
            let driver = MutationDriver(
                seed: seed,
                configuration: MutationDriverConfiguration(mutationsPerTick: 5)
            )
            var all: [Mutation] = []
            for tick in 0 ..< 60 {
                all += driver.step(store: store, visibleRange: tick ..< (tick + 30))
            }
            return all
        }
        #expect(run() == run())
    }

    @Test("Reset replays the stream from the start")
    func resetRewindsTheStream() {
        // A fresh store for the replay: mutation choice depends on the target's current
        // content, so replaying against an already-mutated store would prove nothing.
        let driver = MutationDriver(seed: seed)
        let first = driver.step(store: makeStore(), visibleRange: 0 ..< 30)
        driver.reset()
        let second = driver.step(store: makeStore(), visibleRange: 0 ..< 30)
        #expect(first == second)
        #expect(driver.appliedCount == second.count)
    }

    @Test("Zero mutations per tick is a no-op")
    func zeroRateDoesNothing() {
        let store = makeStore()
        let driver = MutationDriver(
            seed: seed,
            configuration: MutationDriverConfiguration(mutationsPerTick: 0)
        )
        #expect(driver.step(store: store, visibleRange: 0 ..< 10).isEmpty)
        #expect(store.appliedMutationCount == 0)
    }
}

@Suite("Pagination driver")
@MainActor
struct PaginationDriverTests {
    private let seed: UInt64 = 0x7777_8888_9999_AAAA

    @Test("The manual trigger always prepends a full batch")
    func manualPrepend() {
        let store = TimelineStore(seed: seed, initialEventCount: 200)
        let driver = PaginationDriver()
        var observed: Range<Int>?
        driver.didPrepend = { observed = $0 }

        let inserted = driver.prependNow(store: store)
        #expect(inserted == 0 ..< 50)
        #expect(observed == 0 ..< 50)
        #expect(driver.manualPrependCount == 1)
        #expect(driver.automaticPrependCount == 0)
        #expect(store.items.count == 250)
    }

    @Test("willPrepend fires before the store changes")
    func anchorSnapshotHappensFirst() {
        let store = TimelineStore(seed: seed, initialEventCount: 200)
        let driver = PaginationDriver()
        var countAtSnapshot: Int?
        driver.willPrepend = { countAtSnapshot = store.items.count }
        driver.prependNow(store: store)
        #expect(countAtSnapshot == 200)
        #expect(store.items.count == 250)
    }

    @Test("Automatic pagination arms inside the trigger band only")
    func automaticTriggerBand() {
        let store = TimelineStore(seed: seed, initialEventCount: 200)
        var now = Date(timeIntervalSince1970: 0)
        let driver = PaginationDriver(
            configuration: PaginationDriverConfiguration(triggerDistance: 600),
            clock: { now }
        )

        #expect(driver.viewportDidScroll(distanceFromTop: 5_000, store: store) == nil)
        #expect(driver.viewportDidScroll(distanceFromTop: 400, store: store) == 0 ..< 50)
        // The cooldown suppresses the immediate follow-up.
        #expect(driver.viewportDidScroll(distanceFromTop: 400, store: store) == nil)
        now = now.addingTimeInterval(1)
        #expect(driver.viewportDidScroll(distanceFromTop: 400, store: store) == 0 ..< 50)
        #expect(driver.automaticPrependCount == 2)
        #expect(store.items.count == 300)
    }

    @Test("Automatic pagination can be switched off")
    func automaticCanBeDisabled() {
        let store = TimelineStore(seed: seed, initialEventCount: 200)
        let driver = PaginationDriver(
            configuration: PaginationDriverConfiguration(isAutomatic: false)
        )
        #expect(driver.viewportDidScroll(distanceFromTop: 0, store: store) == nil)
        #expect(store.items.count == 200)
    }
}

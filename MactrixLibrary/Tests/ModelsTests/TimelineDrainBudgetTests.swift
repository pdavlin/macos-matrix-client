import Foundation
import Models
import Testing

/// The cadence-aware drain budget behind MATRIX-64.
///
/// The property that matters is not the millisecond figure at any one refresh rate. It is
/// that throughput stays above what the mutation storm produces at every refresh rate the
/// drain can be paced at, because a drain slower than the storm grows the queue without
/// bound.
struct TimelineDrainBudgetTests {
    /// Measured cost of applying one row: the reload rebuilds the visible view, the height
    /// note measures the offscreen one. From the MATRIX-57 storm profiler.
    private static let rowCostSeconds: CFTimeInterval = 0.0026

    /// Row updates a 10 Hz storm of six mutations produces per second. This is
    /// `MutationDriverConfiguration.default` in the spike harness, and SCENARIOS.md §4.
    private static let stormRowsPerSecond: Double = 60

    /// Rows one drain admits, modelling `drainRowUpdates(budget:)`'s loop with a fixed row
    /// cost: the first row always runs, and each further row runs only when the last one's
    /// cost still fits. The real loop charges each row what the previous one actually took.
    private func rowsPerDrain(budget: CFTimeInterval, rowCost: CFTimeInterval) -> Int {
        var applied = 0
        var spent: CFTimeInterval = 0
        var lastRowCost: CFTimeInterval = 0
        while spent + lastRowCost <= budget {
            spent += rowCost
            lastRowCost = rowCost
            applied += 1
            // The real loop stops when the queue empties; here only the budget stops it.
            if applied > 1000 { break }
        }
        return applied
    }

    private func capacityRowsPerSecond(hertz: Double) -> Double {
        let budget = TimelineDrainBudget.budget(forFrameInterval: 1.0 / hertz)
        return Double(rowsPerDrain(budget: budget, rowCost: Self.rowCostSeconds)) * hertz
    }

    @Test
    func sixtyHertzKeepsTheOriginalFlatBudget() {
        // MATRIX-57 shipped a flat 6ms calibrated against a 60 Hz frame. The share form has
        // to reproduce it there, or this is a new budget rather than a re-expression of one.
        let budget = TimelineDrainBudget.budget(forFrameInterval: 1.0 / 60.0)
        #expect(abs(budget - 0.006) < 0.0001)
    }

    @Test
    func oneHundredTwentyHertzTakesTheSameShareOfASmallerFrame() {
        let interval = 1.0 / 120.0
        let budget = TimelineDrainBudget.budget(forFrameInterval: interval)
        #expect(abs(budget / interval - TimelineDrainBudget.frameShare) < 0.0001)
        // A flat 6ms would have been 72% of this frame.
        #expect(budget < 0.006)
    }

    @Test
    func throughputClearsTheStormAtEveryPacedRefreshRate() {
        // The queue grows without bound the moment capacity drops under production, so this
        // is the one property the budget must hold at every rate a display link reports.
        for hertz in [30.0, 60.0, 90.0, 120.0, 144.0, 240.0] {
            let capacity = capacityRowsPerSecond(hertz: hertz)
            #expect(
                capacity >= Self.stormRowsPerSecond,
                "capacity \(capacity) rows/s at \(hertz)Hz is under the storm's \(Self.stormRowsPerSecond) rows/s"
            )
        }
    }

    @Test
    func throughputHoldsTheDesignedTwoTimesHeadroomFromSixtyToOneHundredTwentyHertz() {
        // The interval cancels out of capacity, so 60 and 120 admit different row counts per
        // callback and the same rows per second. That is the point of the share form.
        #expect(capacityRowsPerSecond(hertz: 60) == capacityRowsPerSecond(hertz: 120))
        #expect(capacityRowsPerSecond(hertz: 60) >= 2 * Self.stormRowsPerSecond)
    }

    @Test
    func aStalledLinkCannotHandOneDrainTheWholeFrame() {
        // A link reporting a half-second interval is stalled, not slow. Unclamped, the share
        // would give one drain 180ms and freeze the window.
        let budget = TimelineDrainBudget.budget(forFrameInterval: 0.5)
        #expect(budget <= TimelineDrainBudget.maximumFrameInterval * TimelineDrainBudget.frameShare)
        #expect(budget < 0.02)
    }

    @Test
    func anUnusableIntervalFallsBackToTheSixtyHertzBudget() {
        // The first callback after attach, or a link that has not settled, can report zero.
        #expect(TimelineDrainBudget.budget(forFrameInterval: 0) == TimelineDrainBudget.budget(forFrameInterval: 1.0 / 60.0))
        #expect(TimelineDrainBudget.budget(forFrameInterval: -1) == TimelineDrainBudget.budget(forFrameInterval: 1.0 / 60.0))
        #expect(TimelineDrainBudget.budget(forFrameInterval: .nan) == TimelineDrainBudget.budget(forFrameInterval: 1.0 / 60.0))
    }

    @Test
    func everyDrainAppliesAtLeastOneRow() {
        // A row is atomic: the budget decides whether to start another, never whether to
        // start the first. Without that a fast display would stall the queue completely.
        let tinyBudget = TimelineDrainBudget.budget(forFrameInterval: TimelineDrainBudget.minimumFrameInterval)
        #expect(rowsPerDrain(budget: tinyBudget, rowCost: Self.rowCostSeconds) >= 1)
    }
}

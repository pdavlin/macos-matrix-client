import Foundation
import QuartzCore

/// Cost attribution for the diff-driven update path (MATRIX-57).
///
/// Off unless `MACTRIX_TIMELINE_PROFILE=1` is in the environment, which is read
/// once. Disabled, every entry point is a load of a `static let` and a branch:
/// nothing is timed, allocated or printed, and the accumulators stay empty.
///
/// It exists because a storm frame-time failure cannot be attributed from frame
/// times alone. The gate records what a frame cost, not which part of the update
/// spent it. The split this produces — the row reload against the height note,
/// and the offscreen measurement inside that note — is what identifies a cost as
/// SwiftUI layout rather than table plumbing.
///
/// Two streams, because the work now lands in two places: the batch, which
/// applies structural changes and queues the rest, and the drain, which spends
/// a frame budget on the queue. A batch is no longer the unit a frame pays.
///
/// Main-actor isolated because the update path it measures is. The accumulators
/// are plain statics and carry no synchronisation.
@MainActor
enum TimelineStormProfiler {
    static let enabled = ProcessInfo.processInfo.environment["MACTRIX_TIMELINE_PROFILE"] == "1"

    /// Batches between printed summaries. A summary per batch costs more than
    /// the batch it describes at a 10Hz storm, and perturbs what it measures.
    private static let reportInterval = 100

    /// What one pass of the update path reports about itself. Times are
    /// milliseconds.
    struct BatchTiming {
        var updates: Int
        /// Content-only updates this batch handed to the drain queue.
        var queuedRows: Int
        /// Rows the structural part of the batch inserted or removed.
        var structuralRows: Int
        /// Snapshot apply plus the scroll-anchor compensation. Zero for a
        /// content-only batch, which now touches no rows at all.
        var applyMs: Double
        var totalMs: Double
    }

    /// What one frame's drain reports about itself.
    struct DrainTiming {
        var rows: Int
        /// Rows inside the viewport, which the drain applies first.
        var visibleRows: Int
        /// Rows whose height fingerprint was unchanged, so the drain reloaded
        /// them without re-measuring (MATRIX-63). Against `rows`, this is the
        /// share of a storm the fingerprint takes off the measurement path.
        var skippedMeasures: Int
        var reloadMs: Double
        var noteMs: Double
        var totalMs: Double
        /// Rows still queued when the budget ran out. A non-zero p95 here with
        /// a zero max at the end of a run is the queue keeping up.
        var remaining: Int
    }

    /// A timing plus what the hooks accumulated underneath it.
    struct Sample<Timing> {
        var timing: Timing
        /// Offscreen measurement, which the height note calls synchronously on
        /// every cache miss.
        var measureMs: Double
        var measureCount: Int
        /// Time inside the data-source closure. Separates view construction from
        /// the layout the reload forces around it.
        var providerMs: Double
        var providerCount: Int
        var recycledCount: Int
    }

    private static var batches: [Sample<BatchTiming>] = []
    private static var drains: [Sample<DrainTiming>] = []
    private static var measureMs: Double = 0
    private static var measureCount = 0
    private static var providerMs: Double = 0
    private static var providerCount = 0
    private static var recycledCount = 0

    /// Reads the clock only when enabled, so a disabled caller pays one branch.
    static func now() -> CFTimeInterval {
        enabled ? CACurrentMediaTime() : 0
    }

    static func elapsedMilliseconds(since started: CFTimeInterval) -> Double {
        enabled ? (CACurrentMediaTime() - started) * 1000 : 0
    }

    static func milliseconds(from started: CFTimeInterval, to finished: CFTimeInterval) -> Double {
        (finished - started) * 1000
    }

    static func beginBatch() {
        resetAccumulators()
    }

    static func beginDrain() {
        resetAccumulators()
    }

    static func recordMeasure(_ milliseconds: Double) {
        guard enabled else { return }
        measureMs += milliseconds
        measureCount += 1
    }

    static func recordProvider(since started: CFTimeInterval, recycled: Bool) {
        guard enabled else { return }
        providerMs += elapsedMilliseconds(since: started)
        providerCount += 1
        if recycled { recycledCount += 1 }
    }

    static func endBatch(_ timing: BatchTiming) {
        guard enabled else { return }
        batches.append(sample(timing))
        if batches.count.isMultiple(of: reportInterval) { report() }
    }

    static func endDrain(_ timing: DrainTiming) {
        guard enabled else { return }
        drains.append(sample(timing))
    }

    /// Prints the distribution so far. Percentiles, not just means: the gate
    /// scores p95, and a mean hides the batch that misses the frame.
    static func report() {
        guard enabled else { return }
        if !batches.isEmpty {
            print("[StormProfile] \(batches.count) batches")
            for (name, values) in batchSeries() {
                print(line(name, values))
            }
        }
        guard !drains.isEmpty else { return }
        print("[StormProfile] \(drains.count) drains")
        for (name, values) in drainSeries() {
            print(line(name, values))
        }
        // Per-drain percentiles answer "did a frame miss"; these answer "how
        // much of the storm never reached the measurement path" (MATRIX-63),
        // which a distribution over small per-drain counts hides.
        let rows = drains.reduce(0) { $0 + $1.timing.rows }
        let skipped = drains.reduce(0) { $0 + $1.timing.skippedMeasures }
        let measures = drains.reduce(0) { $0 + $1.measureCount }
        let skipShare = rows > 0 ? Double(skipped) / Double(rows) * 100 : 0
        print(
            "  totals: rows \(rows)  measures skipped \(skipped) (\(format(skipShare))%)"
                + "  offscreen measures \(measures)"
        )
    }

    static func reset() {
        guard enabled else { return }
        batches.removeAll()
        drains.removeAll()
    }

    private static func resetAccumulators() {
        guard enabled else { return }
        measureMs = 0
        measureCount = 0
        providerMs = 0
        providerCount = 0
        recycledCount = 0
    }

    private static func sample<Timing>(_ timing: Timing) -> Sample<Timing> {
        Sample(
            timing: timing,
            measureMs: measureMs,
            measureCount: measureCount,
            providerMs: providerMs,
            providerCount: providerCount,
            recycledCount: recycledCount
        )
    }

    private static func batchSeries() -> [(String, [Double])] {
        [
            ("total ms", batches.map(\.timing.totalMs)),
            ("apply ms", batches.map(\.timing.applyMs)),
            ("measure ms", batches.map(\.measureMs)),
            ("provider ms", batches.map(\.providerMs)),
            ("queued rows", batches.map { Double($0.timing.queuedRows) }),
            ("structural rows", batches.map { Double($0.timing.structuralRows) }),
        ]
    }

    private static func drainSeries() -> [(String, [Double])] {
        [
            ("total ms", drains.map(\.timing.totalMs)),
            ("reload ms", drains.map(\.timing.reloadMs)),
            ("note ms", drains.map(\.timing.noteMs)),
            ("measure ms", drains.map(\.measureMs)),
            ("provider ms", drains.map(\.providerMs)),
            ("applied rows", drains.map { Double($0.timing.rows) }),
            ("visible applied", drains.map { Double($0.timing.visibleRows) }),
            ("measures skipped", drains.map { Double($0.timing.skippedMeasures) }),
            ("measure count", drains.map { Double($0.measureCount) }),
            ("provider count", drains.map { Double($0.providerCount) }),
            ("recycled count", drains.map { Double($0.recycledCount) }),
            ("rows left queued", drains.map { Double($0.timing.remaining) }),
        ]
    }

    private static func line(_ name: String, _ values: [Double]) -> String {
        let mean = values.reduce(0, +) / Double(values.count)
        return "  \(name): p50 \(format(percentile(values, 0.5)))"
            + "  p95 \(format(percentile(values, 0.95)))"
            + "  max \(format(values.max() ?? 0))"
            + "  mean \(format(mean))"
    }

    private static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        guard let last = sorted.indices.last else { return 0 }
        let index = min(last, max(0, Int((Double(sorted.count) * fraction).rounded(.down))))
        return sorted[index]
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

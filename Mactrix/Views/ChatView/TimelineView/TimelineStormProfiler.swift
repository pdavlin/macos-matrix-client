import Foundation
import QuartzCore

/// Cost attribution for one pass of the diff-driven update path (MATRIX-57).
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
/// Main-actor isolated because the update path it measures is. The accumulators
/// are plain statics and carry no synchronisation.
@MainActor
enum TimelineStormProfiler {
    static let enabled = ProcessInfo.processInfo.environment["MACTRIX_TIMELINE_PROFILE"] == "1"

    /// Batches between printed summaries. A summary per batch costs more than
    /// the batch it describes at a 10Hz storm, and perturbs what it measures.
    private static let reportInterval = 100

    /// What the update path itself reports about one pass. Times are
    /// milliseconds.
    struct BatchTiming {
        var updates: Int
        var mutatedRows: Int
        /// Mutated rows inside the viewport. The remainder are mutated rows the
        /// reader cannot see, which is the population a deferral would target.
        var visibleMutated: Int
        var reloadMs: Double
        var noteMs: Double
        var totalMs: Double
    }

    /// One update pass: what the caller reported, plus what the hooks
    /// accumulated underneath it.
    struct Sample {
        var timing: BatchTiming
        /// Offscreen measurement, which the height note calls synchronously on
        /// every cache miss. A subset of `timing.noteMs`.
        var measureMs: Double
        var measureCount: Int
        /// Time inside the data-source closure. Separates view construction from
        /// the layout the reload forces around it.
        var providerMs: Double
        var providerCount: Int
        var recycledCount: Int
    }

    private static var samples: [Sample] = []
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
        guard enabled else { return }
        measureMs = 0
        measureCount = 0
        providerMs = 0
        providerCount = 0
        recycledCount = 0
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
        samples.append(
            Sample(
                timing: timing,
                measureMs: measureMs,
                measureCount: measureCount,
                providerMs: providerMs,
                providerCount: providerCount,
                recycledCount: recycledCount
            )
        )
        if samples.count.isMultiple(of: reportInterval) { report() }
    }

    /// Prints the distribution so far. Percentiles, not just means: the gate
    /// scores p95, and a mean hides the batch that misses the frame.
    static func report() {
        guard enabled, !samples.isEmpty else { return }
        print("[StormProfile] \(samples.count) batches")
        for (name, values) in series() {
            print(line(name, values))
        }
    }

    static func reset() {
        guard enabled else { return }
        samples.removeAll()
    }

    private static func series() -> [(String, [Double])] {
        [
            ("total ms", samples.map(\.timing.totalMs)),
            ("reload ms", samples.map(\.timing.reloadMs)),
            ("note ms", samples.map(\.timing.noteMs)),
            ("measure ms", samples.map(\.measureMs)),
            ("provider ms", samples.map(\.providerMs)),
            ("mutated rows", samples.map { Double($0.timing.mutatedRows) }),
            ("visible mutated", samples.map { Double($0.timing.visibleMutated) }),
            ("measure count", samples.map { Double($0.measureCount) }),
            ("provider count", samples.map { Double($0.providerCount) }),
            ("recycled count", samples.map { Double($0.recycledCount) })
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

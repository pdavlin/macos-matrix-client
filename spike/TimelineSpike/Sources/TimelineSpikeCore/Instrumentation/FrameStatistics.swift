import Foundation

/// Frame-interval statistics kept as a fixed histogram.
///
/// ## Why a histogram
///
/// A run can produce hundreds of thousands of samples. Keeping them all and sorting on
/// every HUD refresh would make the instrument itself a source of hitches. A histogram
/// records in constant time and reads percentiles in a fixed number of steps, and the only
/// cost is quantisation: percentiles are accurate to `bucketWidthMilliseconds`.
///
/// Buckets cover `0 ..< 200 ms` at 0.25 ms, plus one overflow bucket. Anything over 200 ms
/// is a catastrophic stall that the `worst` field records exactly anyway.
public struct FrameStatistics: Sendable, Equatable, Codable {
    public static let bucketWidthMilliseconds: Double = 0.25
    public static let bucketCount = 800

    public private(set) var buckets: [Int]
    public private(set) var overflowCount: Int
    public private(set) var sampleCount: Int
    public private(set) var totalMilliseconds: Double
    public private(set) var worstMilliseconds: Double
    public private(set) var hitchCount: Int
    /// Rolling estimate of the display's nominal frame interval, in milliseconds.
    public private(set) var nominalMilliseconds: Double

    public init(nominalMilliseconds: Double = 1000.0 / 60.0) {
        self.buckets = Array(repeating: 0, count: Self.bucketCount)
        self.overflowCount = 0
        self.sampleCount = 0
        self.totalMilliseconds = 0
        self.worstMilliseconds = 0
        self.hitchCount = 0
        self.nominalMilliseconds = nominalMilliseconds
    }

    public mutating func reset(nominalMilliseconds: Double? = nil) {
        let nominal = nominalMilliseconds ?? self.nominalMilliseconds
        self = FrameStatistics(nominalMilliseconds: nominal)
    }

    /// Records one inter-frame interval.
    ///
    /// - Parameters:
    ///   - interval: measured milliseconds between two consecutive presented frames.
    ///   - nominal: the display's expected interval for that frame, in milliseconds. It is
    ///     smoothed rather than taken raw because variable refresh rate displays report a
    ///     changing target.
    public mutating func record(interval: Double, nominal: Double) {
        guard interval.isFinite, interval > 0 else { return }
        if nominal.isFinite, nominal > 0 {
            nominalMilliseconds = sampleCount == 0
                ? nominal
                : nominalMilliseconds * 0.98 + nominal * 0.02
        }

        sampleCount += 1
        totalMilliseconds += interval
        worstMilliseconds = max(worstMilliseconds, interval)

        // A hitch is a frame that took more than twice the nominal interval, that is, at
        // least one dropped frame.
        if interval > 2 * nominalMilliseconds {
            hitchCount += 1
        }

        let bucket = Int(interval / Self.bucketWidthMilliseconds)
        if bucket < Self.bucketCount {
            buckets[bucket] += 1
        } else {
            overflowCount += 1
        }
    }

    public var meanMilliseconds: Double {
        sampleCount == 0 ? 0 : totalMilliseconds / Double(sampleCount)
    }

    public var hitchRate: Double {
        sampleCount == 0 ? 0 : Double(hitchCount) / Double(sampleCount)
    }

    /// The upper edge of the bucket holding the requested quantile.
    ///
    /// Returns `worstMilliseconds` when the quantile falls in the overflow bucket.
    public func percentile(_ quantile: Double) -> Double {
        guard sampleCount > 0 else { return 0 }
        let clampedQuantile = min(max(quantile, 0), 1)
        // Nearest-rank: the smallest value whose cumulative count reaches the rank.
        let rank = max(1, Int((clampedQuantile * Double(sampleCount)).rounded(.up)))
        var cumulative = 0
        for (index, count) in buckets.enumerated() where count > 0 {
            cumulative += count
            if cumulative >= rank {
                return Double(index + 1) * Self.bucketWidthMilliseconds
            }
        }
        return worstMilliseconds
    }

    public var p50: Double { percentile(0.50) }
    public var p95: Double { percentile(0.95) }
    public var p99: Double { percentile(0.99) }

    /// A flat, JSON-friendly view. The histogram itself is not exported: it is an internal
    /// accumulator, not a result.
    public var summary: Summary {
        Summary(
            sampleCount: sampleCount,
            nominalMilliseconds: nominalMilliseconds,
            meanMilliseconds: meanMilliseconds,
            p50Milliseconds: p50,
            p95Milliseconds: p95,
            p99Milliseconds: p99,
            worstMilliseconds: worstMilliseconds,
            hitchCount: hitchCount,
            hitchRate: hitchRate,
            percentileResolutionMilliseconds: Self.bucketWidthMilliseconds
        )
    }

    public struct Summary: Sendable, Equatable, Codable {
        public var sampleCount: Int
        public var nominalMilliseconds: Double
        public var meanMilliseconds: Double
        public var p50Milliseconds: Double
        public var p95Milliseconds: Double
        public var p99Milliseconds: Double
        public var worstMilliseconds: Double
        public var hitchCount: Int
        public var hitchRate: Double
        public var percentileResolutionMilliseconds: Double
    }
}

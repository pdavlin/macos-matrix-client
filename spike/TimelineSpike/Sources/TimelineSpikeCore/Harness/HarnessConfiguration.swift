import Foundation

/// Everything that changes what the harness generates or does, in one Codable value so a
/// report always carries the settings that produced it.
public struct HarnessConfiguration: Sendable, Equatable, Codable {
    public var seed: UInt64
    public var initialEventCount: Int
    public var mutation: MutationDriverConfiguration
    public var pagination: PaginationDriverConfiguration
    /// Frames a drift sample waits before it closes. See SCENARIOS.md §10.
    ///
    /// It rides in the configuration rather than sitting in a constant because it changes
    /// what the drift numbers mean: a run measured with a six-frame window cannot be put in
    /// the same table as a run measured with three.
    public var driftSettleTicks: Int

    public init(
        seed: UInt64 = 0x5EED_0000_0000_002A,
        initialEventCount: Int = 10_000,
        mutation: MutationDriverConfiguration = .default,
        pagination: PaginationDriverConfiguration = .default,
        driftSettleTicks: Int = AnchorProbe.defaultSettleTicks
    ) {
        self.seed = seed
        self.initialEventCount = initialEventCount
        self.mutation = mutation
        self.pagination = pagination
        self.driftSettleTicks = max(1, driftSettleTicks)
    }

    /// Decoding tolerates a report written before the settle window was configurable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seed = try container.decode(UInt64.self, forKey: .seed)
        initialEventCount = try container.decode(Int.self, forKey: .initialEventCount)
        mutation = try container.decode(MutationDriverConfiguration.self, forKey: .mutation)
        pagination = try container.decode(PaginationDriverConfiguration.self, forKey: .pagination)
        let ticks = try container.decodeIfPresent(Int.self, forKey: .driftSettleTicks)
        driftSettleTicks = max(1, ticks ?? AnchorProbe.defaultSettleTicks)
    }

    public static let `default` = HarnessConfiguration()
}

/// The full result of a measured run.
public struct SpikeReport: Sendable, Codable {
    public struct Counters: Sendable, Codable {
        public var loadedEventCount: Int
        public var oldestIndex: Int
        public var newestIndex: Int
        public var appliedMutationCount: Int
        public var manualPrependCount: Int
        public var automaticPrependCount: Int
        public var prependedEventCount: Int
        public var discardedDriftSampleCount: Int
    }

    public struct Host: Sendable, Codable {
        public var operatingSystem: String
        public var machineModel: String
        public var processorCount: Int
    }

    public var generatedAt: Date
    public var scenario: String
    public var rendererID: String
    public var rendererName: String
    /// Digest of the per-row workload, from `WorkloadFingerprint.value`.
    ///
    /// Two dumps with different fingerprints rendered different content per row. Their
    /// frame times are not comparable, whatever the rest of the file says.
    public var workloadFingerprint: String
    /// Width in points the timeline scroll view had when the report was written.
    ///
    /// Row heights are cached per width, so two dumps taken at different widths measured two
    /// different layouts and their frame times are not comparable. The gate refuses to score a
    /// dump whose width is not the pinned one.
    public var timelineWidth: Double
    /// Viewport height in points at the same moment. Not scored — it records which window the
    /// numbers came from, since viewport height sets how many rows a frame draws.
    public var timelineHeight: Double
    /// Cadence, display and scroller style the run presented under (MATRIX-64).
    ///
    /// Frame thresholds are absolute milliseconds, so the frame quantum is an input to every
    /// one of them. Nil in a dump written before the cadence-pinned epoch, or by hand from
    /// the menu; the gate refuses both rather than scoring them against a 120 Hz bar.
    public var environment: HarnessEnvironment?
    public var configuration: HarnessConfiguration
    public var frame: FrameStatistics.Summary
    public var prependDrift: DriftAccumulator
    public var mutationDrift: DriftAccumulator
    public var counters: Counters
    public var host: Host
}

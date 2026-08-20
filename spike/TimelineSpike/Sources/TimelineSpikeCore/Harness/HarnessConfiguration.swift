import Foundation

/// Everything that changes what the harness generates or does, in one Codable value so a
/// report always carries the settings that produced it.
public struct HarnessConfiguration: Sendable, Equatable, Codable {
    public var seed: UInt64
    public var initialEventCount: Int
    public var mutation: MutationDriverConfiguration
    public var pagination: PaginationDriverConfiguration

    public init(
        seed: UInt64 = 0x5EED_0000_0000_002A,
        initialEventCount: Int = 10_000,
        mutation: MutationDriverConfiguration = .default,
        pagination: PaginationDriverConfiguration = .default
    ) {
        self.seed = seed
        self.initialEventCount = initialEventCount
        self.mutation = mutation
        self.pagination = pagination
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
    public var configuration: HarnessConfiguration
    public var frame: FrameStatistics.Summary
    public var prependDrift: DriftAccumulator
    public var mutationDrift: DriftAccumulator
    public var counters: Counters
    public var host: Host
}

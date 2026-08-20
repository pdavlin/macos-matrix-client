import AppKit
import Foundation
import Observation

/// Owns the store, the drivers and the instruments, and wires them together.
///
/// One object rather than several so a candidate renderer receives exactly one dependency
/// and cannot accidentally opt out of a driver.
///
/// ## Observation and the HUD
///
/// `store` is `@Observable`, so a renderer re-renders when items change. The HUD is not
/// driven that way: reading frame statistics through observation would invalidate the HUD
/// on every display tick and the instrument would then measure itself. Instead the harness
/// publishes `hud`, a plain snapshot refreshed on a 5 Hz timer.
@MainActor
@Observable
public final class SpikeHarness {
    public private(set) var configuration: HarnessConfiguration
    public private(set) var store: TimelineStore
    public private(set) var mutationDriver: MutationDriver
    public private(set) var paginationDriver: PaginationDriver

    @ObservationIgnored public let probe = AnchorProbe()
    @ObservationIgnored public let frameRecorder = FrameRecorder()

    public private(set) var hud = HUDSnapshot()
    public private(set) var isMutating = false
    public private(set) var lastReportURL: URL?
    public private(set) var lastError: String?

    /// Free-text label written into the report, so a run can be tied to a scenario in
    /// SCENARIOS.md.
    public var scenarioLabel: String = "unlabelled"
    /// Identity of the renderer currently on screen. Set by the root view.
    public var activeRenderer: RendererDescriptor?

    @ObservationIgnored private var mutationTimer: Timer?
    @ObservationIgnored private var hudTimer: Timer?

    public init(configuration: HarnessConfiguration = .default) {
        self.configuration = configuration
        self.store = TimelineStore(
            seed: configuration.seed,
            initialEventCount: configuration.initialEventCount
        )
        self.mutationDriver = MutationDriver(
            seed: configuration.seed,
            configuration: configuration.mutation
        )
        self.paginationDriver = PaginationDriver(configuration: configuration.pagination)
        probe.settleTicks = configuration.driftSettleTicks
        wirePagination()
        startHUDTimer()
        frameRecorder.onTick = { [weak self] in
            self?.probe.settle()
        }
    }

    // MARK: - Lifecycle

    /// Rebuilds the whole world from the configuration. Used when the seed or the event
    /// count changes.
    public func rebuild(with configuration: HarnessConfiguration) {
        stopMutating()
        self.configuration = configuration
        store = TimelineStore(
            seed: configuration.seed,
            initialEventCount: configuration.initialEventCount
        )
        mutationDriver = MutationDriver(
            seed: configuration.seed,
            configuration: configuration.mutation
        )
        paginationDriver = PaginationDriver(configuration: configuration.pagination)
        probe.settleTicks = configuration.driftSettleTicks
        wirePagination()
        probe.reset()
        frameRecorder.resetStatistics()
        refreshHUD()
    }

    /// Changes the drift settle window and clears the drift accumulators.
    ///
    /// The accumulators are cleared because samples taken with two different windows are
    /// two different measurements, and averaging them would hide that. See SCENARIOS.md
    /// §10.
    public func updateDriftSettleTicks(_ ticks: Int) {
        let clamped = max(1, ticks)
        guard clamped != configuration.driftSettleTicks else { return }
        configuration.driftSettleTicks = clamped
        probe.settleTicks = clamped
        probe.reset()
        refreshHUD()
    }

    /// Applies driver settings without regenerating the timeline.
    public func updateDriverConfiguration(
        mutation: MutationDriverConfiguration? = nil,
        pagination: PaginationDriverConfiguration? = nil
    ) {
        if let mutation {
            configuration.mutation = mutation
            mutationDriver.configuration = mutation
            if isMutating {
                startMutating()
            }
        }
        if let pagination {
            configuration.pagination = pagination
            paginationDriver.configuration = pagination
        }
    }

    private func wirePagination() {
        paginationDriver.willPrepend = { [weak self] in
            self?.probe.beginSample(kind: .prepend)
        }
    }

    // MARK: - Instrumentation control

    public func attachDisplayLink(to view: NSView) {
        frameRecorder.attach(to: view)
    }

    public func detachDisplayLink() {
        frameRecorder.detach()
    }

    /// Clears frame statistics and drift accumulators. Call it at the start of every
    /// scenario, after the timeline has settled.
    public func resetInstrumentation() {
        frameRecorder.resetStatistics()
        probe.reset()
        refreshHUD()
    }

    // MARK: - Mutation storm

    public func startMutating() {
        mutationTimer?.invalidate()
        let interval = 1.0 / max(0.1, configuration.mutation.ticksPerSecond)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickMutations()
            }
        }
        // `.common` so the storm keeps running while the user drags the scroller.
        RunLoop.main.add(timer, forMode: .common)
        mutationTimer = timer
        isMutating = true
    }

    public func stopMutating() {
        mutationTimer?.invalidate()
        mutationTimer = nil
        isMutating = false
    }

    public func toggleMutating() {
        isMutating ? stopMutating() : startMutating()
    }

    /// Emits exactly one tick, for deterministic manual testing.
    public func mutateOnce() {
        tickMutations()
    }

    private func tickMutations() {
        // Snapshot the anchor before the store changes, but only when no sample is already
        // in flight; overlapping samples would attribute one movement to two causes.
        if !probe.hasPendingSample {
            probe.beginSample(kind: .mutation)
        }
        mutationDriver.step(store: store, visibleRange: probe.visibleRange)
    }

    // MARK: - Pagination

    @discardableResult
    public func prependNow() -> Range<Int> {
        paginationDriver.prependNow(store: store)
    }

    /// Called by the renderer on scroll.
    public func viewportDidScroll(distanceFromTop: Double) {
        paginationDriver.viewportDidScroll(distanceFromTop: distanceFromTop, store: store)
    }

    // MARK: - HUD

    private func startHUDTimer() {
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshHUD()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hudTimer = timer
    }

    private func refreshHUD() {
        let frame = frameRecorder.statistics
        hud = HUDSnapshot(
            isRecording: frameRecorder.isRunning,
            sampleCount: frame.sampleCount,
            nominalMilliseconds: frame.nominalMilliseconds,
            p50: frame.p50,
            p95: frame.p95,
            p99: frame.p99,
            worst: frame.worstMilliseconds,
            hitchCount: frame.hitchCount,
            loadedEventCount: store.items.count,
            oldestIndex: store.oldestIndex,
            visibleCount: probe.visibleIDs.count,
            trackedID: probe.trackedID,
            mutationCount: store.appliedMutationCount,
            prependBatchCount: store.prependedBatchCount,
            prependDrift: probe.prependDrift,
            mutationDrift: probe.mutationDrift,
            discardedDriftSampleCount: probe.discardedSampleCount
        )
    }

    // MARK: - Report

    /// Writes the report as JSON to the process working directory and prints the path.
    @discardableResult
    public func dumpReport() -> URL? {
        do {
            let report = makeReport()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            formatter.timeZone = .current
            let stamp = formatter.string(from: report.generatedAt)
            let name = "timeline-spike-\(report.rendererID)-\(stamp).json"
            let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)

            lastReportURL = url
            lastError = nil
            print("[TimelineSpike] wrote report: \(url.path)")
            return url
        } catch {
            lastError = String(describing: error)
            print("[TimelineSpike] failed to write report: \(error)")
            return nil
        }
    }

    public func makeReport() -> SpikeReport {
        SpikeReport(
            generatedAt: Date(),
            scenario: scenarioLabel,
            rendererID: activeRenderer?.id ?? "unknown",
            rendererName: activeRenderer?.displayName ?? "unknown",
            workloadFingerprint: WorkloadFingerprint.value,
            configuration: configuration,
            frame: frameRecorder.statistics.summary,
            prependDrift: probe.prependDrift,
            mutationDrift: probe.mutationDrift,
            counters: SpikeReport.Counters(
                loadedEventCount: store.items.count,
                oldestIndex: store.oldestIndex,
                newestIndex: store.newestIndex,
                appliedMutationCount: store.appliedMutationCount,
                manualPrependCount: paginationDriver.manualPrependCount,
                automaticPrependCount: paginationDriver.automaticPrependCount,
                prependedEventCount: store.prependedEventCount,
                discardedDriftSampleCount: probe.discardedSampleCount
            ),
            host: SpikeReport.Host(
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                machineModel: Self.machineModel(),
                processorCount: ProcessInfo.processInfo.processorCount
            )
        )
    }

    private static func machineModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return "unknown"
        }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else {
            return "unknown"
        }
        // sysctl returns a null-terminated string; drop the terminator before decoding.
        let payload = bytes.prefix { $0 != 0 }
        return String(decoding: payload, as: UTF8.self)
    }
}

/// A cheap, copyable view of everything the HUD shows.
public struct HUDSnapshot: Sendable, Equatable {
    public var isRecording = false
    public var sampleCount = 0
    public var nominalMilliseconds: Double = 0
    public var p50: Double = 0
    public var p95: Double = 0
    public var p99: Double = 0
    public var worst: Double = 0
    public var hitchCount = 0
    public var loadedEventCount = 0
    public var oldestIndex = 0
    public var visibleCount = 0
    public var trackedID: EventID?
    public var mutationCount = 0
    public var prependBatchCount = 0
    public var prependDrift = DriftAccumulator()
    public var mutationDrift = DriftAccumulator()
    public var discardedDriftSampleCount = 0

    public init() {}

    public init(
        isRecording: Bool,
        sampleCount: Int,
        nominalMilliseconds: Double,
        p50: Double,
        p95: Double,
        p99: Double,
        worst: Double,
        hitchCount: Int,
        loadedEventCount: Int,
        oldestIndex: Int,
        visibleCount: Int,
        trackedID: EventID?,
        mutationCount: Int,
        prependBatchCount: Int,
        prependDrift: DriftAccumulator,
        mutationDrift: DriftAccumulator,
        discardedDriftSampleCount: Int
    ) {
        self.isRecording = isRecording
        self.sampleCount = sampleCount
        self.nominalMilliseconds = nominalMilliseconds
        self.p50 = p50
        self.p95 = p95
        self.p99 = p99
        self.worst = worst
        self.hitchCount = hitchCount
        self.loadedEventCount = loadedEventCount
        self.oldestIndex = oldestIndex
        self.visibleCount = visibleCount
        self.trackedID = trackedID
        self.mutationCount = mutationCount
        self.prependBatchCount = prependBatchCount
        self.prependDrift = prependDrift
        self.mutationDrift = mutationDrift
        self.discardedDriftSampleCount = discardedDriftSampleCount
    }
}

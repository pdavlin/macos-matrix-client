#if DEBUG
    import Foundation
    import TimelineSpikeCore
    import UIKit

    /// One scenario's dump (MATRIX-87).
    ///
    /// The same schema family as the Mac gate's `SpikeReport`: the shared
    /// blocks keep the Mac field names and reuse the spike's own types
    /// (`HarnessConfiguration`, `FrameStatistics.Summary`, `DriftAccumulator`),
    /// so one script reads both. `environment` differs, because a phone has no
    /// scroller style and a simulator has no honest frame timing, and `ios`
    /// carries the counts only this harness can read off the container.
    struct TimelineGateReport: Codable {
        struct Counters: Codable {
            var loadedEventCount: Int
            var oldestIndex: Int
            var newestIndex: Int
            var appliedMutationCount: Int
            var manualPrependCount: Int
            var automaticPrependCount: Int
            var prependedEventCount: Int
            var discardedDriftSampleCount: Int
        }

        struct Host: Codable {
            var operatingSystem: String
            var machineModel: String
            var processorCount: Int
        }

        var generatedAt: Date
        var scenario: String
        var rendererID: String
        var rendererName: String
        var workloadFingerprint: String
        var timelineWidth: Double
        var timelineHeight: Double
        var environment: TimelineGateEnvironment
        var configuration: HarnessConfiguration
        /// Display-link frame intervals. Nil in the simulator, and in every
        /// scenario that does not measure frames: simulator frames are the
        /// Mac GPU's, and say nothing about a phone.
        var frame: FrameStatistics.Summary?
        var prependDrift: DriftAccumulator
        var mutationDrift: DriftAccumulator
        var counters: Counters
        var host: Host
        var ios: TimelineGateMeasurements
        /// The bars this scenario is scored against, with the results.
        var verdicts: [TimelineGateVerdict]

        static let rendererID = "ios-production"
        static let rendererName = "iOS Production Container"
    }

    /// What the iOS harness reads off the production container.
    struct TimelineGateMeasurements: Codable {
        /// The anchor-hold error around one change: how far the container's
        /// own anchor row (the top-most visible row) moved on screen.
        ///
        /// The probe's drift tracks the middle visible row, so it includes
        /// real content movement between the anchor and that row. This number
        /// does not: the compensation promises to hold this row exactly.
        struct AnchorHold: Codable {
            var count = 0
            var worstPoints: Double = 0
            var samplesPoints: [Double] = []

            mutating func record(_ points: Double) {
                count += 1
                worstPoints = max(worstPoints, abs(points))
                samplesPoints.append(points)
            }
        }

        /// The content-update drain, per storm tick.
        struct Drain: Codable {
            /// "quiesced": each tick waits for the queue to empty, so every
            /// count is deterministic. "paced": ticks at the storm rate, as the
            /// Mac S2 does, for frame timing on a device.
            var pacing: String
            var ticks = 0
            /// Frames from a tick until the queue was empty. Timing-dependent:
            /// recorded, never barred.
            var framesTotal = 0
            var framesWorstPerTick = 0
            var backlogWorst = 0
            /// Ticks whose queue did not drain inside the wait cap.
            var stalledTicks = 0
        }

        /// One synchronous full layout pass: the cold load, or a width change.
        struct LayoutPass: Codable {
            var fromWidth: Double
            var toWidth: Double
            var rows: Int
            var remeasured: Int
            /// Wall time of the pass. A simulator number: recorded, never barred.
            var milliseconds: Double
            var microsecondsPerRemeasure: Double
        }

        var rowCount: Int
        /// Storm mutations the store applied in this scenario.
        var mutationsApplied: Int
        /// Height-cache misses in the scenario: one offscreen row measure each.
        var remeasureCount: Int
        var cacheLookups: Int
        /// Every drift sample the probe closed, not only its last 40.
        var driftSamples: [DriftSample]
        var anchorHold: AnchorHold?
        var drain: Drain?
        var layoutPasses: [LayoutPass]
        /// The layout's `prepare()` passes. Each one walks every row's cached
        /// height, so their count is a cost the container controls.
        var layoutPrepares: Int
        var fetchRequestCount: Int
    }

    /// One bar, and how this run did against it.
    struct TimelineGateVerdict: Codable {
        var metric: String
        var value: Double
        /// "<=", ">=" or "==".
        var comparison: String
        var bar: Double
        var passed: Bool

        init(_ metric: String, _ value: Double, _ comparison: String, _ bar: Double) {
            self.metric = metric
            self.value = value
            self.comparison = comparison
            self.bar = bar
            switch comparison {
            case "<=": passed = value <= bar
            case ">=": passed = value >= bar
            default: passed = value == bar
            }
        }

        var summaryLine: String {
            "\(passed ? "PASS" : "FAIL") \(metric) = \(value) (bar \(comparison) \(bar))"
        }
    }

    /// Where the run happened, and whether its frame numbers mean anything.
    struct TimelineGateEnvironment: Codable {
        /// "simulator" or "device".
        var kind: String
        var deviceModel: String
        var systemVersion: String
        var screenPointWidth: Double
        var screenPointHeight: Double
        var screenScale: Double
        var maximumFramesPerSecond: Int
        var contentSizeCategory: String
        /// False for an `-Onone` build. The Mac gate measured debug SwiftUI at
        /// ~7x the release cost, so a device frame pass refuses one.
        var optimized: Bool
        /// What the pinned display link delivered in the calibration spin.
        var cadence: CadenceMeasurement?
        /// True only on a device, optimized, at the pinned cadence.
        var frameMetricsScored: Bool

        var isSimulator: Bool { kind == "simulator" }

        @MainActor
        static func current(screen: UIScreen?, cadence: CadenceMeasurement?) -> TimelineGateEnvironment {
            #if targetEnvironment(simulator)
                let kind = "simulator"
                let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown"
            #else
                let kind = "device"
                let model = machineIdentifier()
            #endif
            let optimized = !_isDebugAssertConfiguration()
            return TimelineGateEnvironment(
                kind: kind,
                deviceModel: model,
                systemVersion: UIDevice.current.systemVersion,
                screenPointWidth: Double(screen?.bounds.width ?? 0),
                screenPointHeight: Double(screen?.bounds.height ?? 0),
                screenScale: Double(screen?.scale ?? 0),
                maximumFramesPerSecond: screen?.maximumFramesPerSecond ?? 0,
                contentSizeCategory: UIApplication.shared.preferredContentSizeCategory.rawValue,
                optimized: optimized,
                cadence: cadence,
                frameMetricsScored: kind == "device" && optimized && cadence?.isHonored == true
            )
        }

        /// `hw.machine`, for example `iPhone18,1`.
        static func machineIdentifier() -> String {
            var info = utsname()
            unsafe uname(&info)
            let bytes = Mirror(reflecting: info.machine).children
                .compactMap { $0.value as? CChar }
                .prefix { $0 != 0 }
                .map { UInt8(bitPattern: $0) }
            return String(bytes: bytes, encoding: .utf8) ?? "unknown"
        }
    }
#endif

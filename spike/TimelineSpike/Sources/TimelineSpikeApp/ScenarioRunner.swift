import AppKit
import Foundation
import TimelineSpikeCore

/// Command-line options that drive a scenario without a human at the window.
///
/// The window still opens — a timeline cannot be measured without a real
/// display link, a real clip view and real row layout — but nothing has to be
/// clicked. That is what turns the harness from a lab bench into a gate.
struct RunnerOptions {
    var rendererID: String
    var scenarios: [Scenario]
    var outputDirectory: URL
    /// Seconds a timed scenario measures for. The protocol says 60; the gate
    /// runs shorter by default so a PR check does not take five minutes.
    var duration: TimeInterval
    var quitWhenDone: Bool

    enum Scenario: String, CaseIterable {
        /// Cold sweep from the newest end to the oldest end of the loaded window.
        case s1
        /// Mutation storm, viewport parked mid-timeline.
        case s2
        /// Mutation storm while sweeping.
        case s3
        /// Twenty deliberate prepends with a tracked event on screen.
        case s4
    }

    /// Parses `--renderer`, `--scenario`, `--duration`, `--out` and `--keep-open`.
    /// Returns `nil` when no `--scenario` was given, which is the interactive case.
    static func parse(_ arguments: [String]) -> RunnerOptions? {
        var rendererID = ProductionRendererID.value
        var scenarios: [Scenario] = []
        var duration: TimeInterval = 20
        var output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var quitWhenDone = true

        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            let next = arguments.index(after: index) < arguments.endIndex ? arguments[arguments.index(after: index)] : nil
            switch argument {
            case "--renderer":
                if let next { rendererID = next }
                index = arguments.index(after: index)
            case "--scenario":
                if let next {
                    scenarios += next.split(separator: ",").compactMap { Scenario(rawValue: String($0).lowercased()) }
                }
                index = arguments.index(after: index)
            case "--duration":
                if let next, let value = TimeInterval(next) { duration = value }
                index = arguments.index(after: index)
            case "--out":
                if let next { output = URL(fileURLWithPath: next) }
                index = arguments.index(after: index)
            case "--keep-open":
                quitWhenDone = false
            default:
                break
            }
            index = arguments.index(after: index)
        }

        guard !scenarios.isEmpty else { return nil }
        return RunnerOptions(
            rendererID: rendererID,
            scenarios: scenarios,
            outputDirectory: output,
            duration: duration,
            quitWhenDone: quitWhenDone
        )
    }
}

/// The renderer id the gate measures. Named here rather than typed as a string
/// literal in three places.
enum ProductionRendererID {
    static let value = "m1-production"
}

/// Drives the scenarios in `SCENARIOS.md` from a timer instead of from a hand.
///
/// A machine-driven sweep is not a trackpad drag, so numbers from here are not
/// interchangeable with the hand-driven S-13/S-14 dumps. They are interchangeable
/// with each other, which is what a regression gate needs: run every candidate
/// through the same driver and compare those.
@MainActor
final class ScenarioRunner {
    private let harness: SpikeHarness
    private let options: RunnerOptions
    private var writtenReports: [URL] = []

    init(harness: SpikeHarness, options: RunnerOptions) {
        self.harness = harness
        self.options = options
    }

    /// Length of the cadence calibration spin, in seconds.
    ///
    /// Two seconds is ~240 samples at the pinned rate: far more than a median needs, and
    /// short enough that it does not show up in the gate's runtime.
    private static let calibrationSeconds: TimeInterval = 2

    /// Exit status when the run refuses to measure. Matches `evaluate-gate.py`'s REFUSED
    /// code, and `run-gate.sh` runs under `set -e`, so a refusal stops the script before it
    /// can score whatever stale dumps are on disk.
    private static let refusalExitCode: Int32 = 3

    func start() {
        Task { @MainActor in
            // Before anything settles: the pinned frame is an input to every number
            // recorded below, so it has to be applied before the first layout.
            await PinnedHarnessGeometry.pinWindow()
            // The cadence is an input to every frame number the same way the width is, so
            // the request goes in before anything is measured. It reaches a link that is
            // already running as well as the next one.
            harness.pinDisplayLinkCadence(hertz: PinnedCadence.hertz)
            // Let the window come up, the table tile and the first layout settle
            // before anything is measured.
            await Self.sleep(seconds: 3)
            print("[TimelineSpike] timeline viewport: \(NSStringFromSize(TimelineViewport.currentSize()))")
            await calibrateCadence()
            for scenario in options.scenarios {
                await run(scenario)
            }
            print("[TimelineSpike] runner finished. Reports:")
            for url in writtenReports {
                print("[TimelineSpike]   \(url.path)")
            }
            if options.quitWhenDone {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// Measures the frame quantum the display link is really delivering, and stops the run
    /// when it is not the pinned one.
    ///
    /// The spin scrolls rather than sitting idle: the scenarios are measured while the
    /// viewport moves, and a cadence read from a still window is not evidence about one that
    /// does not stand still.
    ///
    /// A refusal exits the process. Degrading quietly is what produced the three unreadable
    /// MATRIX-57 acceptance sessions — one at 60 Hz on an external panel, one where adaptive
    /// refresh moved the quantum mid-session — and an absolute millisecond threshold scored
    /// against an unknown quantum is not a measurement.
    private func calibrateCadence() async {
        harness.beginCadenceCalibration()
        if let driver = ScrollDriver(ticks: harness.frameRecorder) {
            await driver.settleAtStart()
            await driver.sweep(for: Self.calibrationSeconds)
        } else {
            print("[TimelineSpike] runner: no scroll view for the calibration spin, measuring an idle window")
            await Self.sleep(seconds: Self.calibrationSeconds)
        }
        let environment = harness.endCadenceCalibration()
        print("[TimelineSpike] environment: \(environment.summaryLine)")

        guard environment.cadence.isHonored else {
            let cadence = environment.cadence
            print(
                "[TimelineSpike] refusing to measure: the display link delivered "
                    + String(format: "%.1f", cadence.measuredHertz)
                    + "Hz (frame quantum "
                    + String(format: "%.3f", cadence.quantumP50Milliseconds)
                    + "ms over \(cadence.sampleCount) samples), not the pinned "
                    + String(format: "%g", PinnedCadence.hertz)
                    + "Hz."
            )
            print(
                "[TimelineSpike] display: \(environment.display.localizedName), panel ceiling "
                    + "\(environment.display.maximumFramesPerSecond)Hz, \(environment.scrollerStyle) scrollers."
            )
            print(
                "[TimelineSpike] frame thresholds are absolute milliseconds, so a dump recorded at "
                    + "another quantum is not comparable with the baseline. Run on a display that can "
                    + "hold \(String(format: "%g", PinnedCadence.hertz))Hz — see spike/GATE.md, "
                    + "\"The pinned environment\"."
            )
            exit(Self.refusalExitCode)
        }
    }

    private func run(_ scenario: RunnerOptions.Scenario) async {
        harness.scenarioLabel = "\(scenario.rawValue)-automated"
        // Every scenario in the protocol runs with automatic pagination off, so
        // a prepend only happens when the scenario asks for one.
        harness.updateDriverConfiguration(
            pagination: PaginationDriverConfiguration(
                batchSize: harness.configuration.pagination.batchSize,
                triggerDistance: harness.configuration.pagination.triggerDistance,
                minimumInterval: harness.configuration.pagination.minimumInterval,
                isAutomatic: false
            )
        )

        guard let driver = ScrollDriver(ticks: harness.frameRecorder) else {
            print("[TimelineSpike] runner: no scroll view found, cannot run \(scenario.rawValue)")
            return
        }

        await driver.settleAtStart()
        harness.resetInstrumentation()

        switch scenario {
        case .s1:
            await driver.sweep(for: options.duration)
        case .s2:
            await driver.seek(toFraction: 0.5)
            await Self.sleep(seconds: 1)
            harness.resetInstrumentation()
            harness.startMutating()
            await Self.sleep(seconds: options.duration)
            harness.stopMutating()
        case .s3:
            await driver.seek(toFraction: 0.5)
            harness.resetInstrumentation()
            harness.startMutating()
            await driver.oscillate(for: options.duration)
            harness.stopMutating()
        case .s4:
            // Park a tracked event mid-viewport near the oldest end, the way the
            // protocol asks, then prepend deliberately.
            await driver.seek(toFraction: 0.92)
            await Self.sleep(seconds: 1)
            harness.resetInstrumentation()
            await Self.sleep(seconds: 0.5)
            for _ in 0 ..< 20 {
                harness.prependNow()
                await Self.sleep(seconds: 1)
            }
        }

        await Self.sleep(seconds: 1)
        if let url = harness.dumpReport(to: options.outputDirectory) {
            writtenReports.append(url)
        }
    }

    private static func sleep(seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

/// Moves a clip view the way a trackpad would, without a trackpad.
///
/// Renderer-agnostic on purpose. The AppKit candidate's table is flipped and
/// oldest-first; the production container's is unflipped and newest-first, so
/// "older" is a different direction in each. The driver reads where the
/// timeline parks itself on load — always the newest end — and treats the other
/// extreme as older.
///
/// ## Pacing
///
/// Every move this driver makes is written from a display-link callback, never from a
/// wall-clock sleep. See `drive(for:body:)` for why that distinction is the difference
/// between measuring a renderer and measuring the driver.
@MainActor
struct ScrollDriver {
    private let scrollView: NSScrollView
    private let ticks: FrameRecorder
    private let startsAtOrigin: Bool

    /// - Parameter ticks: the recorder whose display link paces the moves. It is the same
    ///   link the frame statistics come from, deliberately: a driver paced by one clock and
    ///   measured against another is the defect this initializer's signature prevents.
    init?(ticks: FrameRecorder) {
        guard let scrollView = TimelineViewport.scrollView() else { return nil }
        self.scrollView = scrollView
        self.ticks = ticks
        self.startsAtOrigin = scrollView.contentView.bounds.origin.y <= Self.maximumOriginY(of: scrollView) / 2
    }

    private static func maximumOriginY(of scrollView: NSScrollView) -> CGFloat {
        max(0, scrollView.documentView.map(\.frame.height).map { $0 - scrollView.contentView.bounds.height } ?? 0)
    }

    private var maximumOriginY: CGFloat { Self.maximumOriginY(of: scrollView) }

    /// Fraction 0 is the newest end, 1 the oldest, whichever way the table runs.
    private func originY(forFraction fraction: CGFloat) -> CGFloat {
        let travel = maximumOriginY * min(max(0, fraction), 1)
        return startsAtOrigin ? travel : maximumOriginY - travel
    }

    private func currentFraction() -> CGFloat {
        guard maximumOriginY > 0 else { return 0 }
        let origin = scrollView.contentView.bounds.origin.y
        let fraction = origin / maximumOriginY
        return startsAtOrigin ? fraction : 1 - fraction
    }

    private func setOrigin(_ y: CGFloat) {
        let clipView = scrollView.contentView
        clipView.setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: min(max(0, y), maximumOriginY)))
        scrollView.reflectScrolledClipView(clipView)
    }

    func settleAtStart() async {
        setOrigin(originY(forFraction: 0))
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    /// Steps to a position, one frame at a time, so the container sees a scroll
    /// rather than a jump.
    ///
    /// A reposition, not a measurement: every scenario that seeks resets the instruments
    /// afterwards. It is paced off the display link anyway, because one pacing mechanism in
    /// a driver is easier to reason about than two.
    func seek(toFraction target: CGFloat) async {
        let start = currentFraction()
        let distance = abs(target - start)
        guard distance > 0 else { return }
        // The hand-rolled loop crossed the whole range in 600 steps of one frame each. Same
        // speed, expressed as the duration the tick-paced driver takes it in.
        let duration = Double(distance) * Self.seekFrames * PinnedCadence.quantumMilliseconds / 1000
        await drive(for: duration) { elapsed in
            let progress = CGFloat(min(1, elapsed / duration))
            setOrigin(originY(forFraction: start + (target - start) * progress))
        }
        // Land exactly on the target: the last callback lands a fraction of a frame short.
        setOrigin(originY(forFraction: target))
    }

    /// Frames a full-range seek takes. Far faster than reading speed, which is the point —
    /// a seek is setup, and its cost is not in any scenario's numbers.
    private static let seekFrames: Double = 600

    /// Reading speed, in points per second.
    ///
    /// The protocol asks for "a steady 3 to 4 seconds per screen. Do not flick."
    /// A viewport is roughly 800pt, so a screen every 3.2 seconds is 250pt/s.
    /// Traversing all 10k events at that speed takes the better part of an hour,
    /// which is why an automated run measures a band at the right speed rather
    /// than the whole corpus at the wrong one.
    private static let pointsPerSecond: CGFloat = 250
    private static let pacer = ScrollPacer(pointsPerSecond: pointsPerSecond)

    /// A steady drag toward the oldest end for `duration`. This is S1.
    func sweep(for duration: TimeInterval) async {
        let pacer = Self.pacer
        await drive(for: duration) { elapsed in
            setOrigin(originY(forTravel: pacer.travel(elapsed: elapsed)))
        }
    }

    /// Up and down over a band at the same reading speed. This is S3.
    func oscillate(for duration: TimeInterval) async {
        let start = scrollView.contentView.bounds.origin.y
        // Four screens of travel before each reversal: far enough that every row
        // in the band is recycled, close enough to stay a drag rather than a jump.
        let band = scrollView.contentView.bounds.height * 4
        let pacer = Self.pacer
        await drive(for: duration) { elapsed in
            let travelled = pacer.foldedTravel(elapsed: elapsed, band: band)
            setOrigin(start + (startsAtOrigin ? travelled : -travelled))
        }
    }

    /// Wall-clock slack the stall watchdog allows on top of the requested duration.
    ///
    /// Generous, because it is not a quality bar — it exists so a dead display link ends the
    /// run instead of hanging the gate forever.
    private static let stallGraceSeconds: TimeInterval = 2

    /// Calls `body` once per display-link callback, until `duration` of callback time has
    /// passed, then returns.
    ///
    /// ## Why the callback and not a sleep
    ///
    /// The driver used to write the clip view and then sleep `1/120s` of wall clock. At the
    /// pinned 120 Hz cadence (MATRIX-64) that leaves zero headroom: a sleep resumes a little
    /// late, so writes drift across the vsync boundary until one frame receives two of them
    /// and the next receives none. The doubled frame lays out twice the scroll distance,
    /// overruns its deadline, and the recorder books a missed callback as a 16.75ms
    /// interval. That is what put S1's p95 at exactly two frames for *both* renderers in the
    /// MATRIX-64 baselines — a number produced by the driver, not by the renderer.
    ///
    /// Pacing from the callback removes the race by construction. There is exactly one write
    /// per presented frame, and the write happens inside the callback, before that frame
    /// commits, so the layout it causes belongs to the frame the recorder is timing.
    ///
    /// ## Why `body` takes elapsed time
    ///
    /// The offset is a function of callback time, not of how many callbacks arrived. A
    /// dropped callback then shortens nothing: the next one puts the viewport exactly where
    /// the scenario's reading speed says it belongs, so the sweep covers the same rows in
    /// the same duration as any other run. The workload stays the scenario's workload.
    private func drive(for duration: TimeInterval, body: @escaping (TimeInterval) -> Void) async {
        guard duration > 0 else { return }
        let session = DriveSession()
        let recorder = ticks
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.start(continuation: continuation, recorder: recorder, watchdogSeconds: duration + Self.stallGraceSeconds)
            session.token = recorder.addTickObserver { timestamp in
                let elapsed = session.elapsed(at: timestamp)
                body(min(elapsed, duration))
                if elapsed >= duration {
                    session.finish(recorder: recorder)
                }
            }
        }
    }

    /// Absolute origin for a travel distance from the newest end, whichever way
    /// the table runs.
    private func originY(forTravel travel: CGFloat) -> CGFloat {
        startsAtOrigin ? travel : maximumOriginY - travel
    }
}

/// The mutable state of one `ScrollDriver.drive(for:body:)` call.
///
/// A class because the tick observer and the stall watchdog have to see the same
/// already-finished state: a `CheckedContinuation` may be resumed exactly once, and either
/// of them can be the one that gets there first.
@MainActor
private final class DriveSession {
    /// Set by the caller immediately after registering the observer this session finishes.
    var token: FrameRecorder.TickObserverToken?

    private var continuation: CheckedContinuation<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var startTimestamp: CFTimeInterval?

    /// Adopts the continuation and arms the stall watchdog.
    ///
    /// The watchdog is not a quality check — a move that runs a frame or two long is normal
    /// and lands well inside the grace. It exists because a display link that stops
    /// delivering would otherwise hang the gate for good, and a gate that hangs is worse
    /// than one that reports a stall.
    func start(
        continuation: CheckedContinuation<Void, Never>,
        recorder: FrameRecorder,
        watchdogSeconds: TimeInterval
    ) {
        self.continuation = continuation
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, watchdogSeconds) * 1_000_000_000))
            guard !Task.isCancelled, let self, self.isRunning else { return }
            print(
                "[TimelineSpike] scroll driver: the move did not finish within "
                    + String(format: "%.1f", watchdogSeconds)
                    + "s of wall clock. The display link stalled, and this scenario's numbers "
                    + "describe a viewport that stopped moving."
            )
            self.finish(recorder: recorder)
        }
    }

    private var isRunning: Bool { continuation != nil }

    /// Seconds of callback time since the first callback of this move. The first reads zero.
    func elapsed(at timestamp: CFTimeInterval) -> TimeInterval {
        guard let startTimestamp else {
            self.startTimestamp = timestamp
            return 0
        }
        return timestamp - startTimestamp
    }

    /// Detaches the observer, cancels the watchdog and resumes the caller. Idempotent.
    func finish(recorder: FrameRecorder) {
        if let token {
            recorder.removeTickObserver(token)
            self.token = nil
        }
        watchdog?.cancel()
        watchdog = nil
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}

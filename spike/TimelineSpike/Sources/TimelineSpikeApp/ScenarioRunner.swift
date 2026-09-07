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

    func start() {
        Task { @MainActor in
            // Let the window come up, the table tile and the first layout settle
            // before anything is measured.
            await Self.sleep(seconds: 3)
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

        guard let driver = ScrollDriver() else {
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
@MainActor
struct ScrollDriver {
    private let scrollView: NSScrollView
    private let startsAtOrigin: Bool

    init?() {
        guard let contentView = NSApplication.shared.windows.first?.contentView,
              let scrollView = Self.firstScrollView(in: contentView)
        else { return nil }
        self.scrollView = scrollView
        self.startsAtOrigin = scrollView.contentView.bounds.origin.y <= Self.maximumOriginY(of: scrollView) / 2
    }

    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
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
    func seek(toFraction target: CGFloat) async {
        let start = currentFraction()
        let steps = max(1, Int(abs(target - start) * 600))
        for step in 1 ... steps {
            let progress = CGFloat(step) / CGFloat(steps)
            setOrigin(originY(forFraction: start + (target - start) * progress))
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
    }

    /// Reading speed, in points per second.
    ///
    /// The protocol asks for "a steady 3 to 4 seconds per screen. Do not flick."
    /// A viewport is roughly 800pt, so a screen every 3.2 seconds is 250pt/s.
    /// Traversing all 10k events at that speed takes the better part of an hour,
    /// which is why an automated run measures a band at the right speed rather
    /// than the whole corpus at the wrong one.
    private static let pointsPerSecond: CGFloat = 250
    private static let stepInterval: TimeInterval = 1.0 / 120.0

    /// A steady drag toward the oldest end for `duration`. This is S1.
    func sweep(for duration: TimeInterval) async {
        let deadline = Date().addingTimeInterval(duration)
        let step = Self.pointsPerSecond * CGFloat(Self.stepInterval)
        var travelled: CGFloat = 0
        while Date() < deadline {
            travelled += step
            setOrigin(originY(forTravel: travelled))
            try? await Task.sleep(nanoseconds: UInt64(Self.stepInterval * 1_000_000_000))
        }
    }

    /// Up and down over a band at the same reading speed. This is S3.
    func oscillate(for duration: TimeInterval) async {
        let deadline = Date().addingTimeInterval(duration)
        let start = scrollView.contentView.bounds.origin.y
        // Four screens of travel before each reversal: far enough that every row
        // in the band is recycled, close enough to stay a drag rather than a jump.
        let band = scrollView.contentView.bounds.height * 4
        let step = Self.pointsPerSecond * CGFloat(Self.stepInterval)
        var travelled: CGFloat = 0
        var direction: CGFloat = 1
        while Date() < deadline {
            travelled += direction * step
            if travelled >= band || travelled <= 0 {
                direction = -direction
                travelled = min(max(0, travelled), band)
            }
            setOrigin(start + (startsAtOrigin ? travelled : -travelled))
            try? await Task.sleep(nanoseconds: UInt64(Self.stepInterval * 1_000_000_000))
        }
    }

    /// Absolute origin for a travel distance from the newest end, whichever way
    /// the table runs.
    private func originY(forTravel travel: CGFloat) -> CGFloat {
        startsAtOrigin ? travel : maximumOriginY - travel
    }
}

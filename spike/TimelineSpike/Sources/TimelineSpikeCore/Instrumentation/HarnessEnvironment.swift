import AppKit
import Foundation

/// Display cadence the automated gate pins every run to (MATRIX-64).
///
/// Frame thresholds are absolute milliseconds. That only reads as a quality bar when every
/// dump was recorded at the same frame quantum, and on this hardware the quantum is not a
/// property of the code: a clamshell run on an external panel presents at 60 Hz (16.75ms
/// quanta), the built-in ProMotion panel presents at up to 120 Hz (8.5ms quanta), and
/// adaptive refresh moved it mid-session during the three MATRIX-57 acceptance attempts on
/// 2026-09-17. The same binary scored 18.5ms and 29.75ms on the same scenario in that
/// session, and the difference was the display, not the renderer.
///
/// So the gate asks the display link for a fixed rate, measures what it actually got, and
/// records the measurement. A run that did not get the pinned rate is refused rather than
/// scored: a number whose quantum is unknown is worse than no number.
public enum PinnedCadence {
    /// Callback rate requested from the display link under the automated driver.
    public static let hertz: Double = 120

    /// Nominal frame quantum for `hertz`, in milliseconds.
    public static let quantumMilliseconds: Double = 1000 / hertz

    /// Fraction the measured cadence may differ from `hertz` and still be comparable.
    ///
    /// 5% admits the quantisation in a short calibration spin (a p50 taken from a few
    /// hundred samples lands on a real vsync interval, not on the exact nominal) and
    /// refuses anything that is really running at another rate: 60 Hz is 50% off, and a
    /// panel that flaps between 80 and 120 Hz moves the p50 well past this.
    public static let tolerance: Double = 0.05

    /// Whether a measured rate counts as the pinned one.
    public static func isHonored(measuredHertz: Double) -> Bool {
        guard measuredHertz.isFinite, measuredHertz > 0 else { return false }
        return abs(measuredHertz - hertz) / hertz <= tolerance
    }
}

/// What the display link actually delivered during the calibration spin.
///
/// `quantumP50Milliseconds` is the median of consecutive callback deltas, not a mean: one
/// stalled callback moves a mean and cannot move a median, and the quantum is what is being
/// measured here, not the workload.
public struct CadenceMeasurement: Sendable, Equatable, Codable {
    /// Rate asked of the display link, in hertz.
    public var requestedHertz: Double
    /// Rate the callbacks arrived at, in hertz, derived from `quantumP50Milliseconds`.
    public var measuredHertz: Double
    /// Median interval between consecutive callbacks, in milliseconds.
    public var quantumP50Milliseconds: Double
    /// Callback deltas the median was taken from.
    public var sampleCount: Int
    /// True when `measuredHertz` is within `PinnedCadence.tolerance` of `requestedHertz`.
    public var isHonored: Bool

    public init(
        requestedHertz: Double,
        measuredHertz: Double,
        quantumP50Milliseconds: Double,
        sampleCount: Int,
        isHonored: Bool
    ) {
        self.requestedHertz = requestedHertz
        self.measuredHertz = measuredHertz
        self.quantumP50Milliseconds = quantumP50Milliseconds
        self.sampleCount = sampleCount
        self.isHonored = isHonored
    }

    /// Builds a measurement from raw callback deltas in milliseconds.
    public static func make(requestedHertz: Double, intervalsMilliseconds: [Double]) -> CadenceMeasurement {
        let usable = intervalsMilliseconds.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !usable.isEmpty else {
            return CadenceMeasurement(
                requestedHertz: requestedHertz,
                measuredHertz: 0,
                quantumP50Milliseconds: 0,
                sampleCount: 0,
                isHonored: false
            )
        }
        let median = usable[usable.count / 2]
        let measured = 1000 / median
        return CadenceMeasurement(
            requestedHertz: requestedHertz,
            measuredHertz: measured,
            quantumP50Milliseconds: median,
            sampleCount: usable.count,
            isHonored: PinnedCadence.isHonored(measuredHertz: measured)
        )
    }
}

/// Which physical panel the run presented on.
///
/// Recorded because the cadence is a property of this, not of the code: the same machine
/// clamshelled on an external 60 Hz panel and open on its own ProMotion panel are two
/// different measurement rigs.
public struct DisplayIdentity: Sendable, Equatable, Codable {
    public var localizedName: String
    public var pointWidth: Double
    public var pointHeight: Double
    public var backingScaleFactor: Double
    /// The panel's own ceiling, from `NSScreen.maximumFramesPerSecond`. A 60 here means the
    /// pinned 120 cannot be honored on this display at all.
    public var maximumFramesPerSecond: Int

    public init(
        localizedName: String,
        pointWidth: Double,
        pointHeight: Double,
        backingScaleFactor: Double,
        maximumFramesPerSecond: Int
    ) {
        self.localizedName = localizedName
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.backingScaleFactor = backingScaleFactor
        self.maximumFramesPerSecond = maximumFramesPerSecond
    }

    /// The screen the harness window is on, or the main screen when no window is up yet.
    @MainActor
    public static func current() -> DisplayIdentity {
        let window = NSApplication.shared.windows.first(where: { $0.isVisible })
        guard let screen = window?.screen ?? NSScreen.main else {
            return DisplayIdentity(
                localizedName: "unknown",
                pointWidth: 0,
                pointHeight: 0,
                backingScaleFactor: 0,
                maximumFramesPerSecond: 0
            )
        }
        return DisplayIdentity(
            localizedName: screen.localizedName,
            pointWidth: Double(screen.frame.width),
            pointHeight: Double(screen.frame.height),
            backingScaleFactor: Double(screen.backingScaleFactor),
            maximumFramesPerSecond: screen.maximumFramesPerSecond
        )
    }
}

/// Everything about the machine's presentation setup that moves the numbers in a dump.
///
/// The width guard from MATRIX-60 lives in `SpikeReport.timelineWidth`; this carries the two
/// inputs that guard could not see. `scrollerStyle` is here because it *sets* the width —
/// switching macOS to overlay scrollers gives the clip view the scroller's 17pt back — so a
/// dump that disagrees on the style disagrees on the layout even before the cadence question.
public struct HarnessEnvironment: Sendable, Equatable, Codable {
    public var cadence: CadenceMeasurement
    public var display: DisplayIdentity
    /// `"legacy"` when scroll bars are set to always show, `"overlay"` when they are not.
    public var scrollerStyle: String

    public init(cadence: CadenceMeasurement, display: DisplayIdentity, scrollerStyle: String) {
        self.cadence = cadence
        self.display = display
        self.scrollerStyle = scrollerStyle
    }

    /// The scroller style macOS is set to right now.
    @MainActor
    public static func currentScrollerStyle() -> String {
        NSScroller.preferredScrollerStyle == .legacy ? "legacy" : "overlay"
    }

    /// A one-line form for the run log.
    ///
    /// The backing scale is in here rather than only in the dump because it is the field an
    /// operator most needs before a long recording session: a 1x panel rasterizes a quarter
    /// of the pixels a 2x one does for the same point size, and the gate scores a dump
    /// against a baseline recorded at one scale.
    public var summaryLine: String {
        let cadenceText = String(format: "%.1fHz (p50 %.3fms)", cadence.measuredHertz, cadence.quantumP50Milliseconds)
        let displayText = String(format: "%.0fx%.0f@%.0fx", display.pointWidth, display.pointHeight, display.backingScaleFactor)
        return "\(cadenceText) on \(display.localizedName) \(displayText), ceiling "
            + "\(display.maximumFramesPerSecond)Hz, \(scrollerStyle) scrollers"
    }
}

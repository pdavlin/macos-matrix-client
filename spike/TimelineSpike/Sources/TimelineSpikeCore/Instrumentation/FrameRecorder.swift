import AppKit
import Foundation
import QuartzCore

/// Records inter-frame intervals from a `CADisplayLink`.
///
/// `NSView.displayLink(target:selector:)` (macOS 14+) is used rather than the deprecated
/// `CVDisplayLink`: it follows the window onto whichever display it lands on, so the
/// nominal interval is right on a mixed 60 Hz / 120 Hz setup.
///
/// The link is added to `.common` run loop modes. In `.default` alone it would stall during
/// scroll tracking, which is precisely the interval the spike exists to measure.
///
/// What this measures is presentation cadence, not work per frame. A frame that took 24 ms
/// of layout on a 120 Hz display shows up as a ~25 ms interval. That is the right proxy for
/// "the user saw a hitch" and it is what Contract §7 budgets against. It is not a substitute
/// for an Instruments trace when the answer is "why".
///
/// Because the measurement is in absolute milliseconds, the display's own cadence is an
/// input to it. `pinnedHertz` asks the link for a fixed rate and `beginCalibration()` /
/// `endCalibration()` measure what arrived, so the gate can refuse a run that presented at
/// another rate instead of scoring it. See `PinnedCadence`.
@MainActor
public final class FrameRecorder: NSObject {
    // The drift settle window used to live here as `settleTicks`. It is now
    // `AnchorProbe.settleTicks`, an instance property set from
    // `HarnessConfiguration.driftSettleTicks`: it describes the probe, not the recorder,
    // and a scenario with animated height changes needs to raise it.

    public private(set) var statistics = FrameStatistics()
    public private(set) var isRunning = false

    /// Invoked on every display tick, after the interval has been recorded.
    public var onTick: (() -> Void)?

    /// Callback rate requested of the display link, in hertz. `nil` takes the display's own.
    ///
    /// Applied to the live link as well as to the next one, so the driver does not have to
    /// win a race against the renderer mounting. The request is a request — `CADisplayLink`
    /// makes a best-effort attempt at the range, and a 60 Hz panel cannot honor 120. The
    /// calibration pair below is what says whether it did.
    public var pinnedHertz: Double? {
        didSet { applyPinnedRate() }
    }

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    /// Raw callback deltas in milliseconds, collected only between `beginCalibration()` and
    /// `endCalibration()`. Nil the rest of the time so a measured run allocates nothing here.
    private var calibrationIntervals: [Double]?

    override public init() {
        super.init()
    }

    /// Attaches to a view. The view must already be in a window.
    public func attach(to view: NSView) {
        guard displayLink == nil else { return }
        let link = view.displayLink(target: self, selector: #selector(handleTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        applyPinnedRate()
        lastTimestamp = nil
        isRunning = true
    }

    /// Puts `pinnedHertz` on the live link as a fixed range.
    ///
    /// A fixed range, not a preferred one: `minimum == maximum` is the only form that stops
    /// adaptive refresh moving the quantum mid-run, which is what made the MATRIX-57
    /// acceptance dumps unreadable. Clearing `pinnedHertz` does not restore the display's
    /// own range on a link that is already running; detach and attach for that.
    private func applyPinnedRate() {
        guard let displayLink, let pinnedHertz, pinnedHertz > 0 else { return }
        let rate = Float(pinnedHertz)
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
    }

    public func detach() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        isRunning = false
    }

    /// Clears the histogram without dropping the link. Use it between scenarios.
    public func resetStatistics() {
        statistics.reset()
        lastTimestamp = nil
    }

    // MARK: - Cadence calibration

    /// Starts collecting raw callback deltas.
    ///
    /// The histogram cannot answer this question: its buckets are 0.25ms wide, so a 120 Hz
    /// quantum (8.333ms) and its bucket's upper edge (8.5ms) are 2% apart before anything
    /// has gone wrong. A cadence check needs the deltas themselves.
    public func beginCalibration() {
        calibrationIntervals = []
    }

    /// Stops collecting and reports what the link delivered.
    public func endCalibration() -> CadenceMeasurement {
        let intervals = calibrationIntervals ?? []
        calibrationIntervals = nil
        return CadenceMeasurement.make(
            requestedHertz: pinnedHertz ?? 0,
            intervalsMilliseconds: intervals
        )
    }

    @objc
    private func handleTick(_ link: CADisplayLink) {
        let now = link.timestamp
        let nominal = max(0, link.targetTimestamp - link.timestamp) * 1000
        if let previous = lastTimestamp {
            let interval = (now - previous) * 1000
            statistics.record(interval: interval, nominal: nominal)
            if calibrationIntervals != nil {
                calibrationIntervals?.append(interval)
            }
        }
        lastTimestamp = now
        onTick?()
    }
}

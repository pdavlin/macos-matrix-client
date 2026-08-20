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

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    override public init() {
        super.init()
    }

    /// Attaches to a view. The view must already be in a window.
    public func attach(to view: NSView) {
        guard displayLink == nil else { return }
        let link = view.displayLink(target: self, selector: #selector(handleTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = nil
        isRunning = true
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

    @objc
    private func handleTick(_ link: CADisplayLink) {
        let now = link.timestamp
        let nominal = max(0, link.targetTimestamp - link.timestamp) * 1000
        if let previous = lastTimestamp {
            statistics.record(interval: (now - previous) * 1000, nominal: nominal)
        }
        lastTimestamp = now
        onTick?()
    }
}

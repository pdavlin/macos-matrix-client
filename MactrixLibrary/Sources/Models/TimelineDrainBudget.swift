import Foundation

/// How much of a frame the timeline's row-update drain may spend (MATRIX-57, MATRIX-64).
///
/// ## Why this is a share and not a constant
///
/// MATRIX-57 paced the drain against a display link and gave it a flat 6ms per callback,
/// calibrated against a 60 Hz frame: 6ms is roughly a third of 16.67ms, and at ~2.6ms a row
/// it admits two rows per callback, so 120 rows/second against the ~60 rows/second a 10 Hz
/// storm of six rows produces.
///
/// Both halves of that arithmetic move with the refresh rate, and they move in opposite
/// directions:
///
/// - **Capacity** is rows-per-callback times callbacks-per-second. A flat budget keeps
///   rows-per-callback fixed, so capacity *falls* with the refresh rate. 60 Hz is the floor
///   the number was chosen at, not a degradation from it.
/// - **Frame share** is the budget over the frame interval. A flat budget takes a third of a
///   60 Hz frame and **72% of a 120 Hz one**, which leaves the SwiftUI update, the table's
///   own layout and the compositor 2.3ms of an 8.33ms frame on a ProMotion panel.
///
/// Scaling the budget by the measured callback interval fixes the share, and fixing the share
/// happens to fix the capacity too: rows per callback is `budget / rowCost`, so capacity is
/// `(share x interval / rowCost) x (1 / interval)` — the interval cancels. The drain admits
/// two rows per callback at 60 Hz, one at 120 Hz and five at 24 Hz, and sustains the same
/// ~120 rows/second at all three.
public enum TimelineDrainBudget {
    /// Fraction of a frame one drain may spend.
    ///
    /// 0.36 is MATRIX-57's 6ms over a 60 Hz frame, carried across unchanged so this is a
    /// re-expression of the shipped budget rather than a new one. Raising it trades frame
    /// time for queue latency; lowering it below twice a row's cost per 60 Hz frame drops
    /// capacity under what the storm produces, and the queue grows without bound.
    public static let frameShare: Double = 0.36

    /// Shortest callback interval the share is applied to, in seconds (240 Hz).
    ///
    /// Below this the budget would be smaller than a single row, and a row cannot be split:
    /// the drain always runs one. The clamp keeps a bogus interval from a display link that
    /// has not settled from producing a nonsense budget.
    public static let minimumFrameInterval: CFTimeInterval = 1.0 / 240.0

    /// Longest callback interval the share is applied to, in seconds (30 Hz).
    ///
    /// A link reporting slower than this is stalled, not slow. Charging the share against a
    /// half-second interval would hand one drain a 180ms budget and freeze the window.
    public static let maximumFrameInterval: CFTimeInterval = 1.0 / 30.0

    /// Budget for one drain, given the interval the display link reports for the frame it is
    /// pacing.
    ///
    /// - Parameter frameInterval: seconds until the next frame, from
    ///   `CADisplayLink.targetTimestamp - CADisplayLink.timestamp`. A non-finite or
    ///   non-positive value falls back to the 60 Hz interval, which reproduces the flat
    ///   MATRIX-57 budget.
    public static func budget(forFrameInterval frameInterval: CFTimeInterval) -> CFTimeInterval {
        let usable: CFTimeInterval = frameInterval.isFinite && frameInterval > 0
            ? min(max(frameInterval, minimumFrameInterval), maximumFrameInterval)
            : 1.0 / 60.0
        return usable * frameShare
    }
}

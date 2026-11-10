import Foundation

/// Which timeline row shows the jump-to-message flash, and for how long
/// (MATRIX-136).
///
/// A reply tap focuses an event. The timeline container scrolls to its row
/// and, when the scroll lands, flashes that row. This type decides which row
/// flashes, so the AppKit side only draws:
///
/// 1. `request(rowId:)` when a focus scroll starts toward a row.
/// 2. `land(rowId:at:)` when that scroll ends. Only the latest request can
///    start a flash, so a slow scroll toward an old target never flashes.
/// 3. `elapsed(forRowId:at:)` every time a row view is bound to a row. A
///    recycled row view asks it, so the flash continues on the right row
///    and clears on every other row.
///
/// Times are plain seconds on one monotonic clock (the app passes
/// `CACurrentMediaTime()`), so the type stays pure and testable.
public struct TimelineJumpFlash: Equatable, Sendable {
    /// One running flash.
    public struct Flash: Equatable, Sendable {
        /// Identity of the flashing row (`TimelineRow.uniqueId`).
        public let rowId: String
        /// Clock time the flash started at.
        public let startTime: TimeInterval

        public init(rowId: String, startTime: TimeInterval) {
            self.rowId = rowId
            self.startTime = startTime
        }
    }

    /// Total length of one flash, in seconds.
    public let duration: TimeInterval

    /// The row the last focus scroll is heading for, until it lands.
    public private(set) var requestedRowId: String?

    /// The flash that runs now, or ran last.
    public private(set) var current: Flash?

    /// Makes an idle flash state.
    ///
    /// - Parameter duration: total length of one flash, in seconds. Pass
    ///   `MotionToken.jumpFlashDuration`.
    public init(duration: TimeInterval) {
        self.duration = duration
    }

    /// Notes that a focus scroll now heads for `rowId`. A newer request
    /// replaces an older one.
    public mutating func request(rowId: String) {
        requestedRowId = rowId
    }

    /// Notes that a focus scroll landed on `rowId`.
    ///
    /// - Returns: true when the flash starts on `rowId`. False when the
    ///   landing belongs to a request that a newer request replaced, or when
    ///   no request is open.
    @discardableResult
    public mutating func land(rowId: String, at time: TimeInterval) -> Bool {
        guard requestedRowId == rowId else { return false }
        requestedRowId = nil
        current = Flash(rowId: rowId, startTime: time)
        return true
    }

    /// How far into the flash a row view bound to `rowId` must be.
    ///
    /// - Returns: the seconds since the flash started, or nil when the row
    ///   must show no flash: another row flashes, no flash runs, or the flash
    ///   is over.
    public func elapsed(forRowId rowId: String, at time: TimeInterval) -> TimeInterval? {
        guard let current, current.rowId == rowId else { return nil }
        let elapsed = time - current.startTime
        guard elapsed >= 0, elapsed < duration else { return nil }
        return elapsed
    }

    /// The opacity keyframes of the flash wash.
    ///
    /// Without Reduce Motion the wash rises from 0 to the peak at
    /// `peakFraction` of the duration and falls back to 0. With Reduce Motion
    /// it starts at the peak and only falls, so nothing grows or overshoots.
    ///
    /// - Parameters:
    ///   - peakOpacity: the highest wash opacity
    ///     (`MotionToken.jumpFlashPeakOpacity`).
    ///   - peakFraction: where the peak sits, from 0 to 1
    ///     (`TimelineChromeToken.jumpFlashPeakFraction`).
    ///   - reduceMotion: the system Reduce Motion setting.
    public static func keyframes(
        peakOpacity: Double,
        peakFraction: Double,
        reduceMotion: Bool
    ) -> Keyframes {
        if reduceMotion {
            return Keyframes(values: [peakOpacity, 0], keyTimes: [0, 1])
        }
        let peakTime = min(max(peakFraction, 0), 1)
        return Keyframes(values: [0, peakOpacity, 0], keyTimes: [0, peakTime, 1])
    }

    /// Opacity values and their times, as `CAKeyframeAnimation` takes them.
    public struct Keyframes: Equatable, Sendable {
        /// Wash opacity at each keyframe.
        public let values: [Double]
        /// The time of each keyframe, as a fraction of the duration.
        public let keyTimes: [Double]
    }
}

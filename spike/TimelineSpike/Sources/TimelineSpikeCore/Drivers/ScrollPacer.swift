import CoreGraphics
import Foundation

/// Turns elapsed time into a scroll offset at a fixed reading speed.
///
/// ## Why the offset comes from time and not from a step count
///
/// The automated driver used to add a fixed step per wall-clock tick, so the distance a
/// scenario covered depended on how many timer callbacks arrived. Two runs of the same
/// scenario then traversed different rows, and a run that lost callbacks quietly measured a
/// shorter sweep. Deriving the offset from elapsed time instead makes a sweep cover
/// `pointsPerSecond × duration` whatever the callback stream does, so the workload a
/// scenario applies stays the scenario's workload (MATRIX-65).
///
/// Pure arithmetic on purpose: this is the part of the driver worth a unit test, and it has
/// no view, no clock and no display link in it.
public struct ScrollPacer: Sendable, Equatable {
    /// Reading speed, in points per second.
    public let pointsPerSecond: CGFloat

    public init(pointsPerSecond: CGFloat) {
        self.pointsPerSecond = pointsPerSecond
    }

    /// Distance travelled from the start of a sweep, in points.
    ///
    /// Elapsed times at or below zero read as no travel, so a first callback that lands on
    /// the start timestamp does not move the viewport backwards.
    public func travel(elapsed: TimeInterval) -> CGFloat {
        guard elapsed > 0 else { return 0 }
        return pointsPerSecond * CGFloat(elapsed)
    }

    /// The same distance folded into a band, which turns a one-way sweep into an
    /// up-and-down drag.
    ///
    /// A triangle wave, not a saw: the reversal at each end is what recycles every row in
    /// the band, and a saw would jump back to the start instead of dragging back. The
    /// period is `2 × band`, so the fold preserves the speed — the viewport still moves
    /// `pointsPerSecond`, it only changes direction.
    public func foldedTravel(elapsed: TimeInterval, band: CGFloat) -> CGFloat {
        guard band > 0 else { return 0 }
        let distance = travel(elapsed: elapsed)
        let period = band * 2
        let phase = distance.truncatingRemainder(dividingBy: period)
        return phase <= band ? phase : period - phase
    }
}

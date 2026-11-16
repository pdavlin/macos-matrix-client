import Foundation

/// When a repeated read of one source runs next (MATRIX-161, MATRIX-165).
///
/// `ImagePackStore` keeps one per space for the state read, and
/// `OwnServiceAvatarStore` keeps one per space for the profile read. The
/// value holds no clock: each call takes the time, so tests give their own.
///
/// Rules:
/// - A read is due when the last good read is older than the refresh
///   interval, or was never made.
/// - After `maxFailedReads` failed reads in a row, a read is due only when
///   the back-off has passed since the last failure. Then the count starts
///   again.
///
/// Usage:
/// ```swift
/// guard schedule.isDue(at: now, refreshInterval: 300, maxFailedReads: 3, backOff: 300) else { return }
/// do {
///     try await read()
///     schedule.recordSuccess(at: now)
/// } catch {
///     schedule.recordFailure(at: now)
/// }
/// ```
public struct ReadSchedule: Equatable, Sendable {
    /// The time of the last good read, or nil when none was made.
    public private(set) var lastGoodRead: Date?
    /// The time of the last failed read since the last good one.
    public private(set) var lastFailedRead: Date?
    /// The failed reads in a row.
    public private(set) var failedReads = 0

    /// - Parameter lastGoodRead: The time of a good read that a cache file
    ///   recorded, or nil.
    public init(lastGoodRead: Date? = nil) {
        self.lastGoodRead = lastGoodRead
    }

    /// Whether a read is due at `time`. Mutating: when the back-off has
    /// passed, the count of failed reads starts again.
    public mutating func isDue(
        at time: Date,
        refreshInterval: TimeInterval,
        maxFailedReads: Int,
        backOff: TimeInterval
    ) -> Bool {
        if let last = lastGoodRead, time.timeIntervalSince(last) < refreshInterval {
            return false
        }
        guard failedReads >= maxFailedReads else { return true }
        guard let last = lastFailedRead, time.timeIntervalSince(last) >= backOff else {
            return false
        }
        failedReads = 0
        return true
    }

    public mutating func recordSuccess(at time: Date) {
        lastGoodRead = time
        lastFailedRead = nil
        failedReads = 0
    }

    public mutating func recordFailure(at time: Date) {
        lastFailedRead = time
        failedReads += 1
    }
}

import Foundation

// MARK: - Upload state of a media local echo (MATRIX-107)

/// One reading of the SDK's upload progress for a media local echo.
///
/// Mirrors the SDK's `MediaUploadProgress` (an `index` and an
/// `AbstractProgress` of `current` over `total`) without importing it, so the
/// row layer and its tests stay SDK-free.
///
/// `index` is the media step the SDK is uploading inside the one event. The
/// SDK counts a file and its thumbnail as separate media, and a gallery counts
/// every item (and its thumbnail). `current` and `total` are abstract units,
/// not bytes: encryption changes the byte count on the fly, so the SDK reports
/// an estimate. Only their ratio is meaningful.
public struct MediaUploadSample: Equatable, Sendable {
    /// The media step inside the event (thumbnail, file, or gallery item).
    public let index: UInt64
    /// Units uploaded so far.
    public let current: UInt64
    /// Units to upload. Zero means the SDK has no estimate yet.
    public let total: UInt64

    public init(index: UInt64, current: UInt64, total: UInt64) {
        self.index = index
        self.current = current
        self.total = total
    }

    /// Uploaded share in `0...1`, or nil when the SDK has no total yet.
    ///
    /// Clamped, because an estimate can overshoot its own total.
    public var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, Double(current) / Double(total))
    }

    /// Whole percent uploaded, rounded down, or nil without a total.
    ///
    /// Rounded down so the row never claims 100% before the SDK does: 99.6%
    /// shows as 99%.
    public var percent: Int? {
        guard let fraction else { return nil }
        return Int((fraction * 100).rounded(.down))
    }

    /// True when the SDK reports every unit of this step uploaded.
    public var isComplete: Bool {
        total > 0 && current >= total
    }
}

/// What the upload indicator of an own media local echo shows.
///
/// Derived from the SDK's `EventSendState.notSentYet(progress:)`: a nil
/// progress means the echo waits in the send queue, a value means the upload
/// runs. Every other send state (sent, failed, a remote event) has no upload
/// indicator, which callers model as a nil `MediaUploadState?`.
public enum MediaUploadState: Equatable, Sendable {
    /// In the send queue, no upload progress yet. The indicator is
    /// indeterminate.
    case queued
    /// The upload runs. The indicator is determinate when the sample has a
    /// total.
    case uploading(MediaUploadSample)

    /// Uploaded share in `0...1`, or nil for an indeterminate indicator.
    public var fraction: Double? {
        guard case let .uploading(sample) = self else { return nil }
        return sample.fraction
    }

    /// Whole percent uploaded, or nil for an indeterminate indicator.
    public var percent: Int? {
        guard case let .uploading(sample) = self else { return nil }
        return sample.percent
    }
}

// MARK: - Throttle

/// Decides which upload progress ticks are worth a row redraw (MATRIX-107).
///
/// The SDK reports progress on the local echo itself, so every tick is a
/// timeline item update, and every update the container applies is a row
/// reload: a rebuild of the row's SwiftUI view. An upload reports far more
/// ticks than a person can see. This type lets a tick through only when the
/// row would draw something different, and at most once per
/// `minimumInterval`.
///
/// It is height-safe by construction. A dropped tick leaves the container's
/// row at the content it already drew and measured, so no height can go stale.
/// The cost of a dropped tick is freshness only, and the next admitted tick
/// carries the newest item whole.
///
/// Pure value logic: the caller supplies the clock, so the tests drive time.
public struct MediaUploadThrottle: Sendable {
    /// The default shortest gap between two redraws of one row: ten per
    /// second.
    public static let defaultMinimumInterval: TimeInterval = 0.1

    /// What the row last drew, and when.
    private struct Delivery: Sendable {
        let state: MediaUploadState
        let time: TimeInterval
    }

    /// The shortest gap between two redraws of one row.
    public let minimumInterval: TimeInterval
    /// Keyed by row identity. Holds only rows that show an indicator now.
    private var delivered: [String: Delivery] = [:]

    public init(minimumInterval: TimeInterval = MediaUploadThrottle.defaultMinimumInterval) {
        self.minimumInterval = minimumInterval
    }

    /// Number of rows the throttle tracks. For tests and diagnostics.
    public var trackedRowCount: Int { delivered.count }

    /// Decides whether one row update goes to the screen, and records it if
    /// it does.
    ///
    /// - Parameters:
    ///   - rowId: the row's stable identity.
    ///   - state: the upload state the update carries. Nil for every row that
    ///     shows no upload indicator, which always passes.
    ///   - now: the caller's monotonic clock, in seconds.
    /// - Returns: true to apply the update, false to drop it.
    public mutating func admit(rowId: String, state: MediaUploadState?, at now: TimeInterval) -> Bool {
        guard let state else {
            // The common case in a storm: no upload anywhere. Skip the hash.
            if !delivered.isEmpty {
                delivered.removeValue(forKey: rowId)
            }
            return true
        }
        if let last = delivered[rowId] {
            let elapsed = now - last.time
            guard Self.isWorthRedrawing(from: last.state, to: state, elapsed: elapsed, minimumInterval: minimumInterval) else {
                return false
            }
        }
        delivered[rowId] = Delivery(state: state, time: now)
        return true
    }

    /// Stops tracking a row that left the timeline.
    public mutating func forget(rowId: String) {
        guard !delivered.isEmpty else { return }
        delivered.removeValue(forKey: rowId)
    }

    /// Stops tracking every row, for a timeline reset.
    public mutating func removeAll() {
        delivered.removeAll()
    }

    /// The rule, without the bookkeeping.
    ///
    /// A tick passes when it changes what the indicator means, and otherwise
    /// only when the shown percent moved and `minimumInterval` has passed:
    ///
    /// - Queued and uploading swap: always (the indicator changes kind).
    /// - A new `index`: always. The step changed, and if the SDK's progress
    ///   restarts per step, the restart must show.
    /// - The step completes: always, so the row does not stop at 99%.
    /// - The same whole percent: never. The label would not change, and the
    ///   ring moves less than a point.
    /// - Otherwise: when `elapsed >= minimumInterval`.
    ///
    /// - Parameters:
    ///   - old: the state the row draws now.
    ///   - new: the state the update carries.
    ///   - elapsed: seconds since `old` was drawn.
    ///   - minimumInterval: the shortest gap between two redraws.
    /// - Returns: true when the update is worth a redraw.
    public static func isWorthRedrawing(
        from old: MediaUploadState,
        to new: MediaUploadState,
        elapsed: TimeInterval,
        minimumInterval: TimeInterval
    ) -> Bool {
        guard case let .uploading(oldSample) = old, case let .uploading(newSample) = new else {
            // Queued to queued carries no progress to throttle; any other pair
            // changes the indicator's kind.
            return true
        }
        if oldSample.index != newSample.index { return true }
        if newSample.isComplete, !oldSample.isComplete { return true }
        if oldSample.percent == newSample.percent { return false }
        return elapsed >= minimumInterval
    }
}

// MARK: - Row access

public extension TimelineRow {
    /// The upload indicator state of a media row, or nil for every other row.
    ///
    /// Media means the `.media` and `.attachment` row kinds: image, video,
    /// gallery, audio, and file bodies (and stickers, which the app never
    /// sends). A text local echo is queued too, but it draws no indicator, so
    /// it has no upload state here.
    var mediaUploadState: MediaUploadState? {
        guard case let .message(_, event, kind, _) = self else { return nil }
        switch kind {
        case .media, .attachment:
            return event.mediaUploadState
        case .text, .other:
            return nil
        }
    }
}

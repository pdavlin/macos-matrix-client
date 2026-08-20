import CoreGraphics
import Foundation

public enum DriftKind: String, Sendable, Codable, CaseIterable {
    case prepend
    case mutation
}

/// One before/after measurement of a tracked event's on-screen position.
public struct DriftSample: Sendable, Equatable, Codable {
    public var kind: DriftKind
    public var eventID: EventID
    public var beforeOffset: Double
    public var afterOffset: Double

    /// Signed movement in points. Positive means the event moved down the screen.
    public var signedDelta: Double { afterOffset - beforeOffset }
    /// Absolute movement in points. This is the number the S-15 decision compares.
    public var magnitude: Double { abs(signedDelta) }
}

/// Running totals for one drift kind.
public struct DriftAccumulator: Sendable, Equatable, Codable {
    public private(set) var count = 0
    public private(set) var totalMagnitude: Double = 0
    public private(set) var worstMagnitude: Double = 0
    /// Samples inside half a point. Sub-pixel movement is not visible; this is the number
    /// that answers "did the content stay put".
    public private(set) var stableCount = 0
    public private(set) var recent: [DriftSample] = []

    public static let recentLimit = 40
    public static let stabilityThreshold: Double = 0.5

    public init() {}

    public mutating func record(_ sample: DriftSample) {
        count += 1
        totalMagnitude += sample.magnitude
        worstMagnitude = max(worstMagnitude, sample.magnitude)
        if sample.magnitude <= Self.stabilityThreshold {
            stableCount += 1
        }
        recent.append(sample)
        if recent.count > Self.recentLimit {
            recent.removeFirst(recent.count - Self.recentLimit)
        }
    }

    public var meanMagnitude: Double {
        count == 0 ? 0 : totalMagnitude / Double(count)
    }

    public var stableFraction: Double {
        count == 0 ? 1 : Double(stableCount) / Double(count)
    }

    public mutating func reset() {
        self = DriftAccumulator()
    }
}

/// Measures how far a tracked on-screen event moves when the timeline changes underneath
/// it.
///
/// ## The renderer contract
///
/// A candidate renderer must do exactly two things:
///
/// 1. Call `reportVisible(_:)` whenever the set of on-screen items changes. Order matters:
///    top of the viewport first. The probe uses this to choose a tracking target and the
///    mutation driver uses it to split on-screen from off-screen targets.
/// 2. Call `reportOffset(_:for:)` for `trackedID` whenever that item's position changes.
///    The offset is in **points from the top edge of the viewport, increasing downward**.
///    A SwiftUI candidate reads `frame(in: .named(...)).minY` against a coordinate space on
///    the scroll view; an AppKit candidate reads `convert(rowRect, to: clipView).minY`
///    **minus `clipView.bounds.origin.y`** — the document view's frame lives in the clip
///    view's bounds space and scrolling moves the bounds origin, so the raw converted
///    value registers every scroll as drift (cost S-14 real debugging time).
///    Both must exclude the scroll position itself, otherwise every scroll registers as
///    drift.
///
/// The probe does the rest. Around a prepend or a mutation the harness calls
/// `beginSample(kind:)`, then `settle()` once per frame; after `settleTicks` frames the
/// sample closes with whatever offset the renderer last reported.
///
/// A pending sample is discarded, not recorded as zero, when the tracked event leaves the
/// viewport before it settles. Recording it would flatter a renderer that scrolled the
/// anchor off screen entirely.
@MainActor
public final class AnchorProbe {
    /// Frames a sample waits before it closes.
    ///
    /// Three is enough for a change that lands in the next layout pass and is presented on
    /// the frame after that, with one frame of margin. See SCENARIOS.md §10 for when to
    /// raise it.
    public nonisolated static let defaultSettleTicks = 3

    /// The settle window in frames. Always at least 1: a zero-tick window would close the
    /// sample inside `beginSample`, before the change it is measuring has been laid out.
    public var settleTicks: Int {
        didSet { settleTicks = max(1, settleTicks) }
    }

    public private(set) var visibleIDs: [EventID] = []
    public private(set) var visibleRange: Range<Int>?
    public private(set) var trackedID: EventID?
    public private(set) var trackedOffset: Double?

    public private(set) var prependDrift = DriftAccumulator()
    public private(set) var mutationDrift = DriftAccumulator()
    public private(set) var lastSample: DriftSample?
    public private(set) var discardedSampleCount = 0

    private var pending: PendingSample?

    private struct PendingSample {
        var kind: DriftKind
        var eventID: EventID
        var beforeOffset: Double
        var ticksRemaining: Int
    }

    public init(settleTicks: Int = AnchorProbe.defaultSettleTicks) {
        self.settleTicks = max(1, settleTicks)
    }

    // MARK: - Renderer callbacks

    /// Reports the on-screen items, topmost first, along with their item-index range.
    public func reportVisible(_ ids: [EventID], range: Range<Int>?) {
        visibleIDs = ids
        visibleRange = range
        retargetIfNeeded()
    }

    /// Reports the tracked item's offset from the top of the viewport.
    ///
    /// Calls for other identifiers are ignored, so a renderer may report every visible row
    /// without corrupting the measurement.
    public func reportOffset(_ offset: Double, for id: EventID) {
        guard id == trackedID else { return }
        trackedOffset = offset
    }

    // MARK: - Sampling

    /// Snapshots the tracked event's position. Call immediately before mutating the store.
    ///
    /// Returns `false` when there is nothing to track, which is the correct outcome before
    /// the renderer has laid out for the first time.
    @discardableResult
    public func beginSample(kind: DriftKind) -> Bool {
        guard let trackedID, let trackedOffset else { return false }
        pending = PendingSample(
            kind: kind,
            eventID: trackedID,
            beforeOffset: trackedOffset,
            ticksRemaining: settleTicks
        )
        return true
    }

    /// Advances a pending sample by one frame. Call from the display link.
    public func settle() {
        guard var sample = pending else { return }
        sample.ticksRemaining -= 1
        if sample.ticksRemaining > 0 {
            pending = sample
            return
        }
        pending = nil

        guard sample.eventID == trackedID, let after = trackedOffset else {
            discardedSampleCount += 1
            return
        }
        let closed = DriftSample(
            kind: sample.kind,
            eventID: sample.eventID,
            beforeOffset: sample.beforeOffset,
            afterOffset: after
        )
        lastSample = closed
        switch sample.kind {
        case .prepend: prependDrift.record(closed)
        case .mutation: mutationDrift.record(closed)
        }
    }

    public var hasPendingSample: Bool { pending != nil }

    public func reset() {
        prependDrift.reset()
        mutationDrift.reset()
        lastSample = nil
        pending = nil
        discardedSampleCount = 0
    }

    // MARK: - Tracking target

    /// Picks the middle visible item as the tracking target.
    ///
    /// The middle, not the top: an item at the very top edge is the one a renderer is most
    /// likely to recycle or clip during a prepend, which would discard the sample rather
    /// than measure it.
    private func retargetIfNeeded() {
        if let trackedID, visibleIDs.contains(trackedID) {
            return
        }
        guard !visibleIDs.isEmpty else {
            trackedID = nil
            trackedOffset = nil
            return
        }
        trackedID = visibleIDs[visibleIDs.count / 2]
        trackedOffset = nil
    }
}

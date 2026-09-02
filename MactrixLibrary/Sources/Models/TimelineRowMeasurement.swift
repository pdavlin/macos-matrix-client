import CoreGraphics
import Foundation

/// Pure measurement math for timeline rows (S-32).
///
/// The container answers `tableView(_:heightOfRow:)` from a
/// `TimelineRowHeightCache`; on a miss it measures the row offscreen — the
/// mechanism the 2026-08-20 timeline decision selected. The measurement
/// *source* (an offscreen hosting view in the app target) is injected as a
/// function, so everything here is deterministic and platform-neutral:
/// row + width + token set in, height out.
public enum TimelineRowMeasurement {
    /// Normalizes a raw measured height into a row height the table can use.
    ///
    /// Matches the inherited container's clamp exactly (`max(height, 1)`):
    /// zero- or undefined-height rows cause `NSTableView` layout issues, and
    /// a non-finite measurement must never poison the layout. No rounding is
    /// applied — heights stay identical to what the offscreen measurement
    /// produced before this story.
    public static func normalizedHeight(_ measured: CGFloat) -> CGFloat {
        guard measured.isFinite else { return 1 }
        return max(measured, 1)
    }

    /// Height of one row at one width, through an injected measurer.
    ///
    /// The width is clamped to a minimum of 1 before measuring so a
    /// zero-width layout pass (a table mid-setup) cannot produce degenerate
    /// heights, and the result is normalized via `normalizedHeight(_:)`.
    public static func height(
        of row: TimelineRow,
        width: CGFloat,
        measuredBy measure: (TimelineRow, CGFloat) -> CGFloat
    ) -> CGFloat {
        normalizedHeight(measure(row, max(width, 1)))
    }
}

/// Row-height cache keyed by (row id, width, token set), with revision-based
/// invalidation on row content change (S-32).
///
/// One entry per row id: the entry stores the width, token set, and content
/// revision it was measured under, and a lookup hits only when all three
/// match. A width change, a token change, or a content mutation (revision
/// bump) therefore misses and re-measures exactly the rows it affects —
/// content-only updates that leave a row's revision alone never re-measure it.
///
/// `TokenSet` is generic so the model layer stays free of the Tokens module;
/// the app instantiates it with its typography token value.
public struct TimelineRowHeightCache<TokenSet: Hashable> {
    /// Hit/miss counters, exposed so the container can log cache behavior.
    public struct Stats: Equatable {
        public var hits: Int
        public var misses: Int

        public var lookups: Int { hits + misses }

        public init(hits: Int = 0, misses: Int = 0) {
            self.hits = hits
            self.misses = misses
        }
    }

    private struct Entry {
        var width: CGFloat
        var tokens: TokenSet
        var revision: Int
        var height: CGFloat
    }

    private var entries: [String: Entry] = [:]

    public private(set) var stats = Stats()

    /// Number of rows currently cached.
    public var count: Int { entries.count }

    public init() {}

    /// Returns the cached height for the row, measuring on a miss.
    ///
    /// - Parameters:
    ///   - row: the row to size.
    ///   - width: the layout width the row must fit.
    ///   - tokens: the token set the row renders under.
    ///   - revision: the row's content revision; bump it whenever the row's
    ///     content changes to invalidate the cached height.
    ///   - measure: the measurement source, called only on a miss.
    public mutating func height(
        for row: TimelineRow,
        width: CGFloat,
        tokens: TokenSet,
        revision: Int,
        measure: (TimelineRow, CGFloat) -> CGFloat
    ) -> CGFloat {
        let id = row.uniqueId
        if let entry = entries[id], entry.width == width, entry.tokens == tokens, entry.revision == revision {
            stats.hits += 1
            return entry.height
        }
        stats.misses += 1
        let height = TimelineRowMeasurement.height(of: row, width: width, measuredBy: measure)
        entries[id] = Entry(width: width, tokens: tokens, revision: revision, height: height)
        return height
    }

    /// The cached height for a row id, if any. Inspection only — does not
    /// count as a lookup.
    public func cachedHeight(forRowId rowId: String) -> CGFloat? {
        entries[rowId]?.height
    }

    /// Drops the cached height for one row.
    public mutating func invalidate(rowId: String) {
        entries[rowId] = nil
    }

    /// Drops every cached height.
    public mutating func invalidateAll() {
        entries = [:]
    }

    /// Drops cached heights for rows no longer in the timeline, bounding the
    /// cache to the live row set.
    public mutating func retain(rowIds: Set<String>) {
        entries = entries.filter { rowIds.contains($0.key) }
    }

    /// Resets the hit/miss counters.
    public mutating func resetStats() {
        stats = Stats()
    }
}

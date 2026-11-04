import CoreGraphics
import Foundation

/// Row heights for a few widths at once, so a width change back to a width
/// already laid out costs no measures (MATRIX-98, iOS).
///
/// Each width holds what a `TimelineRowHeightCache` holds for one: per row,
/// the height measured under a token set and a content revision, a hit only
/// when both still match. A phone rotates between two widths, so two are kept
/// by default; the least recently used width goes first when a new one comes.
///
/// The cache also answers without measuring. `validHeight` is a hit or
/// nothing, and `cachedHeight(forRowId:width:)` returns whatever a width last
/// measured, stale or not, which is what a placeholder needs.
public struct TimelineWidthHeightCache<TokenSet: Hashable> {
    public typealias Stats = TimelineRowHeightCache<TokenSet>.Stats

    /// One flat table keyed by row and width. A table per width nested in a
    /// dictionary copies the inner table on every write in an unoptimized
    /// build, which made a 10k-row cold load quadratic.
    private struct Key: Hashable {
        var rowId: String
        var width: CGFloat
    }

    private struct Entry {
        var tokens: TokenSet
        var revision: Int
        var height: CGFloat
    }

    /// Widths kept at once.
    public let widthCapacity: Int

    private var entries: [Key: Entry] = [:]
    /// Widths in use order, the most recent last.
    private var widthsByUse: [CGFloat] = []

    public private(set) var stats = Stats()

    public init(widthCapacity: Int = 2) {
        self.widthCapacity = max(1, widthCapacity)
    }

    /// The widths that hold heights, the most recently used last.
    public var widths: [CGFloat] { widthsByUse }

    /// Number of heights held at one width.
    public func count(atWidth width: CGFloat) -> Int {
        entries.keys.reduce(0) { $0 + ($1.width == width ? 1 : 0) }
    }

    /// Returns the cached height for the row at `width`, measuring on a miss.
    public mutating func height(
        for row: TimelineRow,
        width: CGFloat,
        tokens: TokenSet,
        revision: Int,
        measure: (TimelineRow, CGFloat) -> CGFloat
    ) -> CGFloat {
        if let height = validHeight(for: row, width: width, tokens: tokens, revision: revision) {
            return height
        }
        stats.misses += 1
        let height = TimelineRowMeasurement.height(of: row, width: width, measuredBy: measure)
        use(width)
        entries[Key(rowId: row.uniqueId, width: width)] = Entry(tokens: tokens, revision: revision, height: height)
        return height
    }

    /// The cached height when it is still valid at `width`, or nil. Never
    /// measures. A valid height counts as a hit; nil counts as nothing,
    /// because the caller decides whether a measure follows.
    public mutating func validHeight(for row: TimelineRow, width: CGFloat, tokens: TokenSet, revision: Int) -> CGFloat? {
        guard let entry = entries[Key(rowId: row.uniqueId, width: width)], entry.tokens == tokens,
              entry.revision == revision
        else {
            return nil
        }
        stats.hits += 1
        use(width)
        return entry.height
    }

    /// The height last measured for a row at `width`, valid or not.
    /// Inspection only: does not count as a lookup.
    public func cachedHeight(forRowId rowId: String, width: CGFloat) -> CGFloat? {
        entries[Key(rowId: rowId, width: width)]?.height
    }

    /// Drops one row's heights at every width.
    public mutating func invalidate(rowId: String) {
        for width in widthsByUse {
            entries[Key(rowId: rowId, width: width)] = nil
        }
    }

    /// Drops every height at every width.
    public mutating func invalidateAll() {
        entries = [:]
        widthsByUse = []
    }

    /// Drops heights for rows no longer in the timeline, at every width.
    public mutating func retain(rowIds: Set<String>) {
        entries = entries.filter { rowIds.contains($0.key.rowId) }
    }

    public mutating func resetStats() {
        stats = Stats()
    }

    /// Marks `width` most recently used, and evicts the least recently used
    /// width past the capacity.
    private mutating func use(_ width: CGFloat) {
        if widthsByUse.last == width { return }
        widthsByUse.removeAll { $0 == width }
        widthsByUse.append(width)
        guard widthsByUse.count > widthCapacity else { return }
        let evicted = Set(widthsByUse.prefix(widthsByUse.count - widthCapacity))
        widthsByUse.removeFirst(evicted.count)
        entries = entries.filter { !evicted.contains($0.key.width) }
    }
}

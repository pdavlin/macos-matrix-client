import CoreGraphics
import TimelineSpikeCore

/// Everything about an item that can change its height, and nothing that cannot.
///
/// The store hands the renderer a whole array on every mutation tick and never says which
/// rows moved, so the renderer has to find them. Diffing the events themselves would mean
/// comparing paragraph strings for all 10k loaded rows at 10 Hz. This fingerprint is six
/// O(1) field reads instead, and it is exact given the store's invariants:
///
/// - `editText` always bumps `editCount`, so a new body can never hide behind an equal
///   fingerprint.
/// - `addReaction` and `removeReaction` change `reactions.count` whenever they add or drop a
///   chip. A tally going from `3` to `4` inside an existing chip leaves the height alone, so
///   ignoring it is correct rather than sloppy.
/// - `startsSenderRun` and `daySeparator` change only at the seam the store re-annotates
///   after a prepend, which this catches for free.
struct SpikeRowFingerprint: Equatable {
    var editCount: Int
    var reactionCount: Int
    var paragraphCount: Int
    var startsSenderRun: Bool
    var hasDaySeparator: Bool
    var isImage: Bool

    init(item: TimelineItem) {
        self.editCount = item.event.editCount
        self.reactionCount = item.event.reactions.count
        switch item.event.content {
        case .text(let body):
            self.paragraphCount = body.paragraphs.count
            self.isImage = false
        case .image:
            self.paragraphCount = 0
            self.isImage = true
        }
        self.startsSenderRun = item.startsSenderRun
        self.hasDaySeparator = item.daySeparator != nil
    }
}

/// Row heights for the loaded window, kept in step with the store by fingerprint diffing.
///
/// `NSTableView` caches heights itself and only re-asks after `noteHeightOfRows(...)`, so the
/// cache exists to answer `tableView(_:heightOfRow:)` in O(1) and, more importantly, to know
/// the exact height delta of every change. Those deltas are what the scroll anchoring is
/// computed from; without them the renderer would be guessing at how far to move the
/// viewport.
struct RowHeightCache {
    /// One row's height change, in table row indices.
    struct HeightChange: Equatable {
        var row: Int
        var delta: CGFloat
    }

    private(set) var heights: [CGFloat] = []
    private(set) var fingerprints: [SpikeRowFingerprint] = []
    private(set) var totalHeight: CGFloat = 0
    private(set) var rowWidth: CGFloat = 0

    var rowCount: Int { heights.count }

    func height(row: Int) -> CGFloat {
        heights.indices.contains(row) ? heights[row] : 0
    }

    /// Measures every row from scratch. Used on first layout and on a width change.
    mutating func rebuild(items: [TimelineItem], rowWidth: CGFloat, model: SpikeRowHeightModel) {
        self.rowWidth = rowWidth
        heights = items.map { model.height(for: $0, rowWidth: rowWidth) }
        fingerprints = items.map { SpikeRowFingerprint(item: $0) }
        totalHeight = heights.reduce(0, +)
    }

    /// Measures a prepended batch and pushes it onto the front.
    ///
    /// - Returns: the height the document gained, which is exactly the distance the viewport
    ///   must move to keep the visible content still.
    @discardableResult
    mutating func insertPrefix(
        _ items: ArraySlice<TimelineItem>,
        model: SpikeRowHeightModel
    ) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        let inserted = items.map { model.height(for: $0, rowWidth: rowWidth) }
        heights.insert(contentsOf: inserted, at: 0)
        fingerprints.insert(contentsOf: items.map { SpikeRowFingerprint(item: $0) }, at: 0)
        let gained = inserted.reduce(0, +)
        totalHeight += gained
        return gained
    }

    /// Re-measures the rows whose fingerprint moved.
    ///
    /// - Parameter items: the store's current window, which must already be the same length
    ///   as the cache. Prepends are absorbed by `insertPrefix` before this runs.
    /// - Returns: the rows to hand to `noteHeightOfRows(withIndexesChanged:)` and the height
    ///   deltas the scroll anchoring needs. A row whose content changed without changing its
    ///   height appears in `changedRows` — its cell still has to be redrawn — but not in
    ///   `changes`.
    mutating func refresh(
        items: [TimelineItem],
        model: SpikeRowHeightModel
    ) -> (changedRows: [Int], changes: [HeightChange]) {
        guard items.count == heights.count else { return ([], []) }
        var changedRows: [Int] = []
        var changes: [HeightChange] = []
        for row in items.indices {
            let fingerprint = SpikeRowFingerprint(item: items[row])
            guard fingerprint != fingerprints[row] else { continue }
            fingerprints[row] = fingerprint
            changedRows.append(row)

            let height = model.height(for: items[row], rowWidth: rowWidth)
            let delta = height - heights[row]
            guard delta != 0 else { continue }
            heights[row] = height
            totalHeight += delta
            changes.append(HeightChange(row: row, delta: delta))
        }
        return (changedRows, changes)
    }
}

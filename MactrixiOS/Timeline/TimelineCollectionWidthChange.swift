import Models
import OSLog
import QuartzCore
import UIKit
import Utils

/// The anchor a width change holds: the anchor row, and where the viewport
/// sat before the change.
struct WidthChangeAnchor {
    let anchor: ScrollAnchor
    let originYBefore: CGFloat
}

/// Width changes without a synchronous full re-measure (MATRIX-98).
///
/// Heights are measured against the width, so a rotation or an iPad split
/// resize used to measure every row on the main thread in one pass (11,000
/// rows, 4.9 to 7.9s in a Debug simulator build). Now the pass that changes
/// the width:
/// - takes every row the cache still holds at the new width (rotating back to
///   a width already laid out is free, see `TimelineWidthHeightCache`),
/// - measures the rows around the anchor row at once, enough to fill the
///   viewport with a margin each side,
/// - and gives every other row its old-width height as a placeholder.
///
/// The drain then measures the placeholder rows in batches inside its frame
/// budget, nearest the viewport first. A batch that changes rows nearer the
/// newest end than the anchor moves the anchor, and the drain's measured-delta
/// compensation (`ScrollAnchorMath`) holds it still, as for any height change.
extension TimelineCollectionController {
    /// How far each side of the pivot row a width change measures at once, in
    /// viewport heights. One viewport covers every row the reader can see
    /// whatever the anchor's position; the half is margin for a scroll.
    static let widthChangeExactReach: CGFloat = 1.5

    /// Rows that still hold a placeholder height.
    var owedWidthRemeasureCount: Int { widthPlaceholders.count }

    func heightsAcrossWidthChange(from oldWidth: CGFloat, to width: CGFloat) -> [CGFloat] {
        let started = CACurrentMediaTime()
        let missesBefore = heightCache.stats.misses
        // Read against the old geometry: the frames the reader still sees.
        let anchor = currentScrollAnchor()
        widthChangeAnchor = anchor.map { WidthChangeAnchor(anchor: $0, originYBefore: originY) }
        let pivot = widthChangePivot(anchor: anchor)

        var heights: [CGFloat] = []
        heights.reserveCapacity(rows.count)
        var placeholders: [String: CGFloat] = [:]
        for row in rows {
            let id = row.uniqueId
            let tokens = cellTokens(for: row)
            let revision = rowRevisions[id] ?? 0
            if let height = heightCache.validHeight(for: row, width: width, tokens: tokens, revision: revision) {
                heights.append(height)
            } else if let placeholder = widthPlaceholders[id] ?? heightCache.cachedHeight(forRowId: id, width: oldWidth) {
                placeholders[id] = placeholder
                heights.append(placeholder)
            } else {
                // A row never laid out has no placeholder to show.
                heights.append(height(of: row, width: width))
            }
        }
        widthPlaceholders = placeholders

        let reach = collectionView.bounds.height * Self.widthChangeExactReach
        heights[pivot] = exactHeight(ofRow: pivot, width: width)
        var low = pivot
        var covered: CGFloat = 0
        while low > 0, covered < reach {
            low -= 1
            heights[low] = exactHeight(ofRow: low, width: width)
            covered += heights[low]
        }
        var high = pivot
        covered = 0
        while high < rows.count - 1, covered < reach {
            high += 1
            heights[high] = exactHeight(ofRow: high, width: width)
            covered += heights[high]
        }
        widthRemeasureQueue = widthRemeasureOrder(outside: low ... high)

        let elapsed = (CACurrentMediaTime() - started) * 1000
        Logger.timelineIOS.info(
            """
            width change \(oldWidth)→\(width): \(self.heightCache.stats.misses - missesBefore) measured now, \
            \(self.widthPlaceholders.count) owed to the drain, \(elapsed)ms
            """
        )
        return heights
    }

    /// Holds the width change's anchor once the pass at the new width ran,
    /// and starts the drain for the rows it left owed.
    func collectionViewDidLayout() {
        if let pending = widthChangeAnchor {
            widthChangeAnchor = nil
            restoreWidthChangeAnchor(pending)
        }
        if !widthRemeasureQueue.isEmpty {
            scheduleRowUpdateDrain()
        }
    }

    /// Measures one owed row at the laid-out width, and drops its placeholder.
    /// The layout reads the new height on its next pass.
    func measureOwedRow(at index: Int) {
        let row = rows[index]
        widthPlaceholders[row.uniqueId] = nil
        _ = height(of: row, width: laidOutWidth)
    }

    /// The next owed row to measure: a visible one first, then the queue's
    /// nearest. Nil when nothing is owed.
    func nextOwedRow(visibleOwed: inout [Int]) -> Int? {
        while let index = visibleOwed.popLast() {
            if rows.indices.contains(index), widthPlaceholders[rows[index].uniqueId] != nil {
                return index
            }
        }
        while let id = widthRemeasureQueue.popLast() {
            guard widthPlaceholders[id] != nil, let index = snapshot.indexOfItem(id),
                  rows.indices.contains(index), rows[index].uniqueId == id
            else { continue }
            return index
        }
        // Whatever is left belongs to rows that left the timeline.
        widthPlaceholders.removeAll()
        return nil
    }

    /// Visible rows that still show a placeholder height.
    func visibleOwedRows() -> [Int] {
        guard !widthPlaceholders.isEmpty else { return [] }
        return collectionView.indexPathsForVisibleItems.map(\.item).filter { index in
            rows.indices.contains(index) && widthPlaceholders[rows[index].uniqueId] != nil
        }
    }

    func clearWidthPlaceholders() {
        widthPlaceholders.removeAll()
        widthRemeasureQueue.removeAll()
    }

    // MARK: - Private

    private func exactHeight(ofRow index: Int, width: CGFloat) -> CGFloat {
        widthPlaceholders[rows[index].uniqueId] = nil
        return height(of: rows[index], width: width)
    }

    /// The row the exact window centers on: the anchor row, or at the newest
    /// end the lowest visible row.
    private func widthChangePivot(anchor: ScrollAnchor?) -> Int {
        if let anchor, let row = snapshot.indexOfItem(anchor.rowId), rows.indices.contains(row) {
            return row
        }
        let viewport = collectionView.bounds
        let visible = layout.geometry.rows(intersectingMinY: viewport.minY, maxY: viewport.maxY)
        if let first = visible.first, rows.indices.contains(first) {
            return first
        }
        return 0
    }

    /// Owed rows outside the exact window, alternating outward from it, in
    /// pop order (the nearest last).
    private func widthRemeasureOrder(outside window: ClosedRange<Int>) -> [String] {
        var order: [String] = []
        order.reserveCapacity(widthPlaceholders.count)
        var below = window.lowerBound - 1
        var above = window.upperBound + 1
        while below >= 0 || above < rows.count {
            if below >= 0 {
                if widthPlaceholders[rows[below].uniqueId] != nil { order.append(rows[below].uniqueId) }
                below -= 1
            }
            if above < rows.count {
                if widthPlaceholders[rows[above].uniqueId] != nil { order.append(rows[above].uniqueId) }
                above += 1
            }
        }
        return order.reversed()
    }

    private func restoreWidthChangeAnchor(_ pending: WidthChangeAnchor) {
        guard let row = snapshot.indexOfItem(pending.anchor.rowId),
              let originAfter = layout.geometry.minY(ofRow: row)
        else { return }
        // From the viewport's position before the change, not its current
        // one: UIKit can clamp the offset to the new content size first.
        let target = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: pending.originYBefore,
            anchorOriginBefore: pending.anchor.originBefore,
            anchorOriginAfter: originAfter,
            maximumOriginY: ScrollAnchorMath.maximumOriginY(
                documentHeight: layout.geometry.contentHeight,
                viewportHeight: collectionView.bounds.height
            )
        )
        guard target != originY else { return }
        isAdjustingScrollAnchor = true
        collectionView.contentOffset = CGPoint(x: collectionView.contentOffset.x, y: target)
        isAdjustingScrollAnchor = false
        scheduleScrollReport()
    }
}

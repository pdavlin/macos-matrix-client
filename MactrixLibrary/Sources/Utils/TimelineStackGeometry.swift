import CoreGraphics

/// Row geometry for a timeline stacked from pre-measured heights (MATRIX-85).
///
/// Rows are laid out in display order, newest first: row 0 starts at the
/// document origin and every later (older) row sits after it. That is the
/// geometry the Mac table gets from its unflipped `NSTableView`, so a
/// back-pagination batch lands at the far end of the document and moves
/// nothing the reader can see.
///
/// The iOS container is a `UICollectionView` with a custom layout. Its layout
/// asks this type for frames and for the rows a rect shows, so the layout
/// stays a thin adapter and the arithmetic stays testable without UIKit.
///
/// Heights come from `TimelineRowHeightCache`, never from self-sizing: a
/// layout that guesses heights cannot hold a prepend still to the point.
public struct TimelineStackGeometry: Equatable, Sendable {
    /// Row heights in display order.
    public let heights: [CGFloat]
    /// Distance of each row's leading edge from the document origin.
    public let offsets: [CGFloat]
    /// Sum of every row height.
    public let contentHeight: CGFloat

    public init(heights: [CGFloat]) {
        self.heights = heights
        var offsets: [CGFloat] = []
        offsets.reserveCapacity(heights.count)
        var running: CGFloat = 0
        for height in heights {
            offsets.append(running)
            running += height
        }
        self.offsets = offsets
        contentHeight = running
    }

    private init(heights: [CGFloat], offsets: [CGFloat], contentHeight: CGFloat) {
        self.heights = heights
        self.offsets = offsets
        self.contentHeight = contentHeight
    }

    public var rowCount: Int { heights.count }

    /// The geometry with some rows' heights replaced, and every other height
    /// kept (MATRIX-98).
    ///
    /// Offsets before the first changed row are reused, and the rest are
    /// summed again from there. That is the same additions in the same order
    /// as `init(heights:)`, so the result equals a full rebuild exactly. Rows
    /// the geometry does not hold are ignored.
    public func replacingHeights(_ changes: [Int: CGFloat]) -> TimelineStackGeometry {
        let valid = changes.filter { heights.indices.contains($0.key) }
        guard let first = valid.keys.min() else { return self }
        var newHeights = heights
        for (row, height) in valid {
            newHeights[row] = height
        }
        var newOffsets = Array(offsets[..<first])
        newOffsets.reserveCapacity(newHeights.count)
        var running = offsets[first]
        for height in newHeights[first...] {
            newOffsets.append(running)
            running += height
        }
        return TimelineStackGeometry(heights: newHeights, offsets: newOffsets, contentHeight: running)
    }

    /// Distance of the row's leading edge from the document origin, or nil for
    /// an index the geometry does not hold.
    public func minY(ofRow row: Int) -> CGFloat? {
        offsets.indices.contains(row) ? offsets[row] : nil
    }

    /// Rows that intersect the span from `minY` to `maxY`, in index order.
    ///
    /// A binary search on both ends, so the cost stays logarithmic in the
    /// timeline length: the layout asks this once per layout pass.
    public func rows(intersectingMinY minY: CGFloat, maxY: CGFloat) -> Range<Int> {
        guard !heights.isEmpty, maxY > minY, maxY > 0, minY < contentHeight else { return 0 ..< 0 }
        let first = lastRow(startingAtOrBefore: max(minY, 0))
        // The last row whose leading edge is strictly before `maxY`: a row that
        // starts exactly at `maxY` touches the span without showing in it.
        var low = first
        var high = heights.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if offsets[mid] < maxY {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return first ..< (low + 1)
    }

    /// The row a scroll anchor holds still: the visible row farthest from the
    /// document origin.
    ///
    /// The origin is the newest end, so this is the visually top-most row, the
    /// one nearest the end a back-pagination batch grows. Nil when no row is
    /// visible.
    public func anchorRow(viewportMinY: CGFloat, viewportMaxY: CGFloat) -> Int? {
        let visible = rows(intersectingMinY: viewportMinY, maxY: viewportMaxY)
        return visible.isEmpty ? nil : visible.upperBound - 1
    }

    /// The last row whose leading edge is at or before `y`.
    private func lastRow(startingAtOrBefore y: CGFloat) -> Int {
        var low = 0
        var high = offsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if offsets[mid] <= y {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}

/// The scroll positions the timeline containers act on.
///
/// The values match the Mac container's literals (`bottomThreshold` and the
/// 200pt pagination trigger in `TimelineScrollAnchor.swift`), so both
/// platforms count "at the bottom" and "near the oldest end" the same way.
/// Both are measured from the document origin at the newest end.
public enum TimelineScrollMetrics {
    /// Distance from the newest end within which the timeline still counts as
    /// scrolled to the bottom.
    public static let bottomThreshold: CGFloat = 40
    /// Distance from the oldest end within which a back-pagination starts.
    public static let paginationThreshold: CGFloat = 200

    public static func isAtBottom(originY: CGFloat) -> Bool {
        originY <= bottomThreshold
    }

    /// True when the viewport is near enough to the oldest end to ask for an
    /// older batch. A document shorter than the viewport is always near it.
    public static func shouldPaginate(originY: CGFloat, documentHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        documentHeight - viewportHeight - originY <= paginationThreshold
    }
}

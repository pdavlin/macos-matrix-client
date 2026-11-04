import UIKit
import Utils

/// Supplies the pre-measured row heights the layout stacks.
@MainActor
protocol TimelineStackLayoutHeightSource: AnyObject {
    /// One height per row, in display order, for rows laid out at `width`.
    func rowHeights(forWidth width: CGFloat) -> [CGFloat]
    /// One row's height at `width`: what an incremental pass re-reads.
    func rowHeight(atRow row: Int, forWidth width: CGFloat) -> CGFloat
}

/// Names the rows whose heights changed, so a pass re-reads only those
/// (MATRIX-98).
final class TimelineStackInvalidationContext: UICollectionViewLayoutInvalidationContext {
    var invalidatedRows = IndexSet()
}

/// A single-column stack fed by pre-measured heights (MATRIX-85).
///
/// This is the iOS twin of the Mac table's `heightOfRow` path: the layout
/// never self-sizes and never estimates. Every frame comes from
/// `TimelineStackGeometry`, built from heights the controller measured
/// offscreen and cached, so a frame read before an update and after it are
/// both exact. That is what the measured-delta anchor needs.
///
/// A pass walks every row only when it must (MATRIX-98): the first pass, a
/// width change, a data-source change, or a full invalidation. A
/// `TimelineStackInvalidationContext` re-reads the rows it names and re-sums
/// the offsets after the first of them. Any other invalidation, such as
/// UIKit's self-sizing check on a cell, leaves the geometry as it is.
///
/// Row 0 (the newest) sits at the document origin. The collection view is
/// flipped vertically, so the origin is drawn at the bottom of the screen and
/// a back-pagination batch grows the far (top) end without moving the
/// viewport. Each cell carries the inverse flip so its content draws upright.
final class TimelineStackLayout: UICollectionViewLayout {
    weak var heightSource: TimelineStackLayoutHeightSource?

    /// The geometry of the last `prepare()`. The controller reads it to
    /// capture and restore the scroll anchor.
    private(set) var geometry = TimelineStackGeometry(heights: [])

    /// Draws a cell upright inside the flipped collection view.
    static let cellTransform = CGAffineTransform(scaleX: 1, y: -1)

    /// The width the geometry was built at.
    private(set) var preparedWidth: CGFloat = 0
    private var needsFullPass = true
    private var rowsToReread = IndexSet()

    override static var invalidationContextClass: AnyClass {
        TimelineStackInvalidationContext.self
    }

    override func invalidateLayout() {
        needsFullPass = true
        super.invalidateLayout()
    }

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        super.invalidateLayout(with: context)
        if context.invalidateEverything || context.invalidateDataSourceCounts {
            needsFullPass = true
        }
        if let context = context as? TimelineStackInvalidationContext {
            rowsToReread.formUnion(context.invalidatedRows)
        }
    }

    /// Re-reads these rows' heights on the next pass, and no others.
    func invalidateHeights(ofRows rows: IndexSet) {
        guard !rows.isEmpty else { return }
        let context = TimelineStackInvalidationContext()
        context.invalidatedRows = rows
        invalidateLayout(with: context)
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let width = collectionView.bounds.width
        // The data source and the height source read the same rows array, but
        // a mismatch must degrade to an empty layout, never to a trap.
        let itemCount = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        defer {
            needsFullPass = false
            rowsToReread = IndexSet()
        }

        if needsFullPass || width != preparedWidth || geometry.rowCount != itemCount {
            let heights = heightSource?.rowHeights(forWidth: width) ?? []
            geometry = TimelineStackGeometry(heights: heights.count == itemCount ? heights : [])
            preparedWidth = width
            return
        }
        guard let heightSource, !rowsToReread.isEmpty else { return }
        var changes: [Int: CGFloat] = [:]
        for row in rowsToReread where row < geometry.rowCount {
            changes[row] = heightSource.rowHeight(atRow: row, forWidth: width)
        }
        geometry = geometry.replacingHeights(changes)
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: geometry.contentHeight)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        geometry.rows(intersectingMinY: rect.minY, maxY: rect.maxY).map { attributes(forRow: $0) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section == 0, indexPath.item < geometry.rowCount else { return nil }
        return attributes(forRow: indexPath.item)
    }

    /// Only a width change invalidates on scroll: heights are measured
    /// against the width, and nothing else about the bounds moves a row.
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }

    /// The layout owns every height, so a cell's own opinion never changes
    /// one. `TimelineCell` returns the attributes it gets, so this is a
    /// second line, not the first.
    override func shouldInvalidateLayout(
        forPreferredLayoutAttributes _: UICollectionViewLayoutAttributes,
        withOriginalAttributes _: UICollectionViewLayoutAttributes
    ) -> Bool {
        false
    }

    /// Frame of one row in document coordinates, or nil past the end.
    func frame(ofRow row: Int) -> CGRect? {
        guard let minY = geometry.minY(ofRow: row) else { return nil }
        return CGRect(x: 0, y: minY, width: collectionView?.bounds.width ?? 0, height: geometry.heights[row])
    }

    private func attributes(forRow row: Int) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: row, section: 0))
        attributes.frame = frame(ofRow: row) ?? .zero
        attributes.transform = Self.cellTransform
        return attributes
    }
}

/// A timeline cell that keeps the frame the layout gives it (MATRIX-98).
///
/// A `UIHostingConfiguration` cell otherwise sizes its SwiftUI content when it
/// appears, and that check re-ran the layout's `prepare()`: 3 times in a 5s
/// scroll inside the safe area, 50 times under a safe-area inset. The height
/// it computed also disagreed with the measured one on tall rows.
final class TimelineCell: UICollectionViewCell {
    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        layoutAttributes
    }
}

/// The timeline's collection view: reports each finished layout pass, so a
/// width change can hold its anchor after the pass that re-laid every row
/// (MATRIX-98).
final class TimelineCollectionView: UICollectionView {
    var didLayoutSubviews: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        didLayoutSubviews?()
    }
}

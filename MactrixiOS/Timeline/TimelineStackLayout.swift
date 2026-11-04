import UIKit
import Utils

/// Supplies the pre-measured row heights the layout stacks.
@MainActor
protocol TimelineStackLayoutHeightSource: AnyObject {
    /// One height per row, in display order, for rows laid out at `width`.
    func rowHeights(forWidth width: CGFloat) -> [CGFloat]
}

/// A single-column stack fed by pre-measured heights (MATRIX-85).
///
/// This is the iOS twin of the Mac table's `heightOfRow` path: the layout
/// never self-sizes and never estimates. Every frame comes from
/// `TimelineStackGeometry`, built from heights the controller measured
/// offscreen and cached, so a frame read before an update and after it are
/// both exact. That is what the measured-delta anchor needs.
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

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let heights = heightSource?.rowHeights(forWidth: collectionView.bounds.width) ?? []
        // The data source and the height source read the same rows array, but
        // a mismatch must degrade to an empty layout, never to a trap.
        let itemCount = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        geometry = TimelineStackGeometry(heights: heights.count == itemCount ? heights : [])
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

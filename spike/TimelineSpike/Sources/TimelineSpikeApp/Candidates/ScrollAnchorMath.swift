import CoreGraphics

/// The arithmetic that keeps the visible content still while the document changes above it.
///
/// `NSTableView` in a flipped document view puts row 0 at the top and grows downward, and
/// `NSClipView.bounds.origin.y` is how far the viewport has travelled from the top of the
/// document. So anything inserted or grown **above** the viewport pushes the content the user
/// is looking at down by exactly that many points, and the fix is to add the same number to
/// the bounds origin in the same layout pass.
///
/// This is separated from the view so it can be tested without a window, because it is the
/// part that is easy to get wrong by a sign.
enum ScrollAnchorMath {
    /// Furthest the viewport can travel before it hits the bottom of the document.
    static func maximumOriginY(documentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        max(0, documentHeight - viewportHeight)
    }

    static func clamped(_ originY: CGFloat, maximumOriginY: CGFloat) -> CGFloat {
        min(max(0, originY), max(0, maximumOriginY))
    }

    /// Where the viewport must sit for a row that moved from `anchorTopBefore` to
    /// `anchorTopAfter` in the document to stay where it is on screen.
    ///
    /// This is the whole anchoring technique in one line. Both tops are in the document's
    /// coordinates and are read from `NSTableView.rect(ofRow:)` either side of the update, so
    /// the answer is right whatever moved the row — a prepend, a height change above it, or
    /// the table deciding to shift things itself.
    ///
    /// `maximumOriginY` must already account for the new document height; call this after the
    /// table has re-tiled, otherwise the clamp caps the very move it is meant to allow.
    static func originRestoringAnchor(
        currentOriginY: CGFloat,
        anchorTopBefore: CGFloat,
        anchorTopAfter: CGFloat,
        maximumOriginY: CGFloat
    ) -> CGFloat {
        clamped(currentOriginY + (anchorTopAfter - anchorTopBefore), maximumOriginY: maximumOriginY)
    }

    /// How far the viewport must move to absorb a set of height changes.
    ///
    /// Only rows strictly above `anchorRow` count. `anchorRow` is the row the top edge of the
    /// viewport sits in: it grows downward from its own top, so it moves the content below it
    /// and leaves the top edge alone. Rows below the anchor are the same case. Compensating
    /// for either of those would be the bug, not the fix — it would drag the anchor row off
    /// the top of the screen every time a visible message gained a reaction.
    static func compensation(
        for changes: [RowHeightCache.HeightChange],
        anchorRow: Int
    ) -> CGFloat {
        changes.reduce(0) { total, change in
            change.row < anchorRow ? total + change.delta : total
        }
    }
}

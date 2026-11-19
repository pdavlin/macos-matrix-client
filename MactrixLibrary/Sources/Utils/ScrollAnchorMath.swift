import CoreGraphics

/// The arithmetic that holds visible content still while the document changes around it.
///
/// A scroll view's `NSClipView.bounds.origin.y` is how far the viewport has travelled from
/// the document's origin. A row's own distance from that same origin comes from
/// `NSTableView.rect(ofRow:)`. The row stays where it is on screen exactly when the two move
/// together, so the whole technique is: read the row's distance before the update, read it
/// again after, and add the difference to the viewport.
///
/// Nothing here assumes which end of the document the origin sits at, so it holds for a
/// flipped table (origin at the oldest end) and for the timeline's unflipped one (origin at
/// the newest end) alike.
///
/// This is separate from the view so it can be tested without a window, because it is the
/// part that is easy to get wrong by a sign.
public enum ScrollAnchorMath {
    /// Furthest the viewport can travel before it runs off the end of the document.
    ///
    /// `minimumOriginY` is the origin at the document's own end: 0, or minus the bottom content
    /// inset when a bar floats over that end (MATRIX-198). A document shorter than the viewport
    /// rests at that end.
    public static func maximumOriginY(
        documentHeight: CGFloat,
        viewportHeight: CGFloat,
        minimumOriginY: CGFloat = 0
    ) -> CGFloat {
        max(minimumOriginY, documentHeight - viewportHeight)
    }

    /// `originY` kept between `minimumOriginY` and `maximumOriginY`. The minimum wins when the
    /// two cross.
    public static func clamped(_ originY: CGFloat, minimumOriginY: CGFloat = 0, maximumOriginY: CGFloat) -> CGFloat {
        min(max(minimumOriginY, originY), max(minimumOriginY, maximumOriginY))
    }

    /// Where the viewport must sit for a row that moved from `anchorOriginBefore` to
    /// `anchorOriginAfter` in the document to stay where it is on screen.
    ///
    /// Both distances are in the document's coordinates and are read from
    /// `NSTableView.rect(ofRow:)` either side of the update, so the answer is right whatever
    /// moved the row — a pagination batch, a height change beyond the viewport, or the table
    /// deciding to shift rows itself.
    ///
    /// `maximumOriginY` must already account for the new document height; call this after the
    /// table has re-tiled, otherwise the clamp caps the very move it is meant to allow.
    public static func originRestoringAnchor(
        currentOriginY: CGFloat,
        anchorOriginBefore: CGFloat,
        anchorOriginAfter: CGFloat,
        minimumOriginY: CGFloat = 0,
        maximumOriginY: CGFloat
    ) -> CGFloat {
        clamped(
            currentOriginY + (anchorOriginAfter - anchorOriginBefore),
            minimumOriginY: minimumOriginY,
            maximumOriginY: maximumOriginY
        )
    }
}

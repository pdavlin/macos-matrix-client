import CoreGraphics
import Tokens

/// Pure sizing math shared by the inline media rows (image and video).
///
/// The inputs mirror the SDK's media-info fields (`UInt64` pixel dimensions,
/// both optional) so the app target can pass them through unconverted, while
/// this module stays free of SDK and AppKit imports.
public enum MediaRowLayout {
    /// Width over height, or nil when either dimension is missing or zero.
    ///
    /// A nil aspect ratio tells the row to let the loaded content size itself.
    public static func aspectRatio(width: UInt64?, height: UInt64?) -> CGFloat? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }

    /// The row-height cap for media with the given intrinsic pixel height.
    ///
    /// Media shorter than the token cap renders at its own height; anything
    /// taller (or of unknown height) is capped at `BubbleToken.mediaMaxHeight`.
    public static func maxHeight(height: UInt64?) -> CGFloat {
        guard let height, height > 0 else { return BubbleToken.mediaMaxHeight }
        return min(CGFloat(height), BubbleToken.mediaMaxHeight)
    }
}

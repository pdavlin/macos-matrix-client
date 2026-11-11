import Foundation

/// Timing of the Mac timeline's floating hover action bar (MATRIX-145).
///
/// The bar's look lives in `DensityToken`, `BubbleToken`, and
/// `ReactionToken`, and its reveal motion in `MotionToken`. This file holds
/// the one value that is the floating bar's own.
public enum HoverBarToken {
    /// How long the timeline must hold still after a scroll before the bar
    /// shows again, in seconds. A scroll hides the bar, because the content
    /// moves under the pointer. Short enough to feel at once, long enough
    /// that the bar does not flash between the frames of a slow scroll.
    public static let scrollSettleDelay: Double = 0.12
}

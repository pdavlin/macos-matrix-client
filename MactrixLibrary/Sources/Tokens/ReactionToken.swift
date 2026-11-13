import SwiftUI

/// Reaction chip and quick-reaction styling (MATRIX-135, visual flair batch).
///
/// The chip is a capsule. The account's own reaction takes an accent tint and
/// an inset accent ring; other reactions take a quiet fill and show a
/// separator ring on hover. The chip's size comes from `DensityToken`
/// (`reactionPadding`, `reactionCountPadding`) and does not change here: the
/// rings are inset strokes, so they never change the chip's frame.
public enum ReactionToken {
    /// Opacity of the accent fill behind the account's own reaction.
    public static let ownFillOpacity: Double = 0.15

    /// Width of the accent ring (own reaction) and the separator ring
    /// (another reaction under the pointer). Drawn inset, inside the chip.
    public static let ringWidth: CGFloat = 1

    /// The saturation of a quick-reaction emoji in the hover action bar while
    /// the pointer is not over it. Zero draws it monochrome.
    public static let quickReactionRestingSaturation: Double = 0

    /// The opacity of a quick-reaction emoji in the hover action bar while the
    /// pointer is not over it.
    public static let quickReactionRestingOpacity: Double = 0.7

    /// The glyph whose box a custom emoji image takes (MATRIX-154). The chip
    /// draws it hidden in the current font, so an image key has the size of
    /// an emoji key at every font size.
    public static let imageSizeReference = "\u{1F44D}"

    /// Corner radius of the neutral square a custom emoji shows while its
    /// image loads.
    public static let imagePlaceholderCornerRadius: CGFloat = 3

    /// Opacity of that square's gray fill.
    public static let imagePlaceholderOpacity: Double = 0.3

    /// The SF Symbol a custom emoji shows when its image does not load.
    public static let imageFailedSystemImage = "face.dashed"
}

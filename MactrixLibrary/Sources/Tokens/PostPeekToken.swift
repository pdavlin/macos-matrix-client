import CoreGraphics

/// Sizes of the post peek popover (MATRIX-201): one X or Bluesky post in a
/// popover on the link that was clicked.
///
/// The popover is navigation layer, so it keeps the system popover material.
/// The post's content inside it is opaque: photos and video draw on a plain
/// fill.
public enum PostPeekToken {
    /// Width of the popover's content.
    public static let width: CGFloat = 400

    /// Tallest the popover's content gets before it scrolls.
    public static let maxHeight: CGFloat = 560

    /// Height of the loading and error states, so the popover does not jump
    /// much when the post arrives.
    public static let statusMinHeight: CGFloat = 96

    /// Padding inside the popover.
    public static let padding: CGFloat = 14

    /// Space between the parts of a post: header, text, media, footer.
    public static let spacing: CGFloat = 10

    /// Side of the author avatar in the header.
    public static let avatarSize: CGFloat = 40

    /// Side of the author avatar in a quoted post.
    public static let quoteAvatarSize: CGFloat = 18

    /// Font size of the post text.
    public static let textSize: CGFloat = 14

    /// Font size of the quoted post's text and of the meta lines (handle,
    /// date, "Replying to").
    public static let secondaryTextSize: CGFloat = 12

    /// Corner radius of the photos, the video, the link card and the quote.
    public static let cornerRadius: CGFloat = 10

    /// Space between photos in a grid.
    public static let mediaSpacing: CGFloat = 2

    /// Tallest a single photo or video draws.
    public static let singleMediaMaxHeight: CGFloat = 320

    /// Height of one cell of a grid of two to four photos.
    public static let gridCellHeight: CGFloat = 140

    /// Height of the link card's image.
    public static let cardImageHeight: CGFloat = 150

    /// Padding inside the link card and the quoted post.
    public static let innerPadding: CGFloat = 10

    /// Width of the border of the link card and the quoted post.
    public static let borderWidth: CGFloat = 1

    /// Opacity of the fill behind a photo that has not loaded.
    public static let placeholderOpacity: Double = 0.12

    /// Side of the play glyph on a video poster.
    public static let playGlyphSize: CGFloat = 44
}

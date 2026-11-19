import CoreGraphics

/// Size and color tokens of the thread panel and the thread chip
/// (MATRIX-183).
///
/// Every mark here is a fill, a stroke, or an overlay of fixed size: none
/// changes a timeline row's height.
public enum ThreadToken {
    // MARK: Panel

    /// Opacity of the accent band behind the thread root in the panel. Half
    /// the focus background (`AccentToken.focusBackgroundOpacity`), so the
    /// root reads as the subject of the panel without looking focused.
    public static let rootBandOpacity: Double = 0.05

    /// Width of the accent bar at the leading edge of the panel's root row.
    public static let rootBarWidth: CGFloat = 2

    /// Space between the title and the subtitle of the panel header.
    public static let headerLineSpacing: CGFloat = 1

    /// Padding inside the panel header.
    public static let headerPadding: CGFloat = 10

    // MARK: Divider

    /// Height of the "N replies" divider row after the panel's root. Same as
    /// the merged timeline's source note (`MergedSourceNoteToken.height`): a
    /// quiet label, not a break in time like a day divider. Models keeps the
    /// same number as `ThreadRepliesDivider.rowHeight`.
    public static let repliesDividerHeight: CGFloat = 28

    /// Font size of the divider label (label-sm).
    public static let repliesDividerFontSize: CGFloat = 11

    /// Space between the label and the hairline on each side.
    public static let repliesDividerSpacing: CGFloat = 8

    // MARK: Chip

    /// Side of a replier avatar in the thread chip. The chip's content never
    /// gets shorter than this, so an avatar that comes or goes does not
    /// change the row height.
    public static let chipAvatarSize: CGFloat = 16

    /// The most replier avatars the chip shows.
    public static let chipMaxAvatars = 3

    /// How much one replier avatar overlaps the one before it.
    public static let chipAvatarOverlap: CGFloat = 4

    /// Width of the ring that sets the avatars apart where they overlap.
    public static let chipAvatarRingWidth: CGFloat = 1.5

    /// Space between the avatars, the count, and the chevron in the chip.
    public static let chipContentSpacing: CGFloat = 5

    /// Space between the chip and the latest reply after it.
    public static let chipLatestReplySpacing: CGFloat = 8
}

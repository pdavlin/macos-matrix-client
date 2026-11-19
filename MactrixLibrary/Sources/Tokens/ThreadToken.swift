import CoreGraphics

/// Size and color tokens of the thread panel and the thread chip
/// (MATRIX-183).
///
/// Every mark here is a fill, a stroke, or an overlay of fixed size: none
/// changes a timeline row's height.
public enum ThreadToken {
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

    /// Space between the reply count and the chevron of the thread chip.
    public static let chipChevronSpacing: CGFloat = 4

    /// Space between the lines and the parts of the thread chip.
    public static let chipSpacing: CGFloat = 2

    /// Width of the thread chip's outline.
    public static let chipBorderWidth: CGFloat = 1
}

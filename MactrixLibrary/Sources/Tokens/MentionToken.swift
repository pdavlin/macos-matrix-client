import CoreGraphics

/// Layout tokens for mentions in the composer (MATRIX-105): the chip and the
/// autocomplete popup.
public enum MentionToken {
    /// Space between the chip edge and its label.
    public static let chipHorizontalPadding: CGFloat = 5

    /// Extra height above and below the chip label. The chip stays inside the
    /// line, so this is small.
    public static let chipVerticalPadding: CGFloat = 1

    /// Opacity of the accent fill behind the chip label.
    public static let chipBackgroundOpacity: CGFloat = 0.18

    /// Avatar size in a popup row.
    public static let rowAvatarSize: CGFloat = 20

    /// Opacity of the accent fill behind the selected popup row.
    public static let selectedRowOpacity: Double = 0.18

    /// Corner radius of a popup row highlight.
    public static let rowCornerRadius: CGFloat = 6
}

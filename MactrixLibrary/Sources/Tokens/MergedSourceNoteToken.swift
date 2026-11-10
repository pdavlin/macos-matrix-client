import CoreGraphics

/// Size and type tokens for the merged timeline's source note (MATRIX-142).
///
/// The note is a decoration row between two runs of messages from different
/// member rooms. Its height is fixed, so the timeline's row measurement can
/// rely on it at every width: the label is one line and truncates.
public enum MergedSourceNoteToken {
    /// Height of the source note row. Smaller than a divider row
    /// (`DensityToken.dividerHeight`, 40 pt): the note labels a run and must
    /// not read as a break in time.
    public static let height: CGFloat = 28

    /// Font size of the label.
    public static let fontSize: CGFloat = 11

    /// Side of the network badge in front of the label. The badge is the
    /// chat list's network badge at a smaller size.
    public static let badgeSize: CGFloat = 14

    /// Space between the badge and the label.
    public static let badgeSpacing: CGFloat = 6
}

import CoreGraphics

/// Layout tokens for the merged chat's target picker chip above the composer
/// text field (MATRIX-143, M2.5-4).
public enum ComposerTargetToken {
    /// The chip's fixed height. The chip never grows, so the composer above
    /// the timeline keeps one height for every target and reason.
    public static let chipHeight: CGFloat = 24

    /// The side of the network badge in the chip.
    public static let badgeSize: CGFloat = 14

    /// The side of the network badge in a menu item.
    public static let menuBadgeSize: CGFloat = 16

    /// Space between the chip edge and its content, left and right.
    public static let horizontalPadding: CGFloat = 8

    /// Space between the parts of the chip.
    public static let spacing: CGFloat = 6

    /// The widest the target name can be before it truncates.
    public static let nameMaxWidth: CGFloat = 240

    /// Opacity of the chip fill, as for the attachment chips.
    public static let backgroundOpacity: Double = 0.08
}

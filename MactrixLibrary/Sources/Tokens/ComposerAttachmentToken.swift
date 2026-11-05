import CoreGraphics

/// Layout tokens for the pending attachment chips above the composer text
/// field (MATRIX-106).
public enum ComposerAttachmentToken {
    /// The side of the square preview or type icon in a chip.
    public static let previewSize: CGFloat = 40

    /// The corner radius of the preview.
    public static let previewCornerRadius: CGFloat = 6

    /// The corner radius of the chip.
    public static let chipCornerRadius: CGFloat = 10

    /// Space between the chip edge and its content.
    public static let chipPadding: CGFloat = 6

    /// The widest the filename can be before it truncates in the middle.
    public static let filenameMaxWidth: CGFloat = 160

    /// Space between chips.
    public static let chipSpacing: CGFloat = 8

    /// Opacity of the chip fill.
    public static let chipBackgroundOpacity: Double = 0.08
}

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// The marker of a music link in a message body (MATRIX-178): a small
/// glyph before the link text, and an underline. Opaque body content, not
/// glass.
public enum MusicLinkToken {
    /// The SF Symbol before the link text.
    public static let glyphSymbolName = "music.note"

    /// The glyph's height as a part of the font's cap height. The glyph sits
    /// on the baseline and stays below the ascender, so the line is no taller.
    public static let glyphHeightScale: CGFloat = 1

    /// The space after the glyph, as a part of the font size.
    public static let glyphTrailingSpaceScale: CGFloat = 0.2

    /// The underline of the link text.
    public static let underlineStyle = NSUnderlineStyle.single

    /// The color of the glyph and the link text.
    public static var tint: PlatformColor {
        #if canImport(AppKit)
            .linkColor
        #else
            .link
        #endif
    }
}

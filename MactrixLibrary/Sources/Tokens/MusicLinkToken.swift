#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// The marker of a music link in a message body (MATRIX-178, MATRIX-187): a
/// small glyph before the link text, and a gradient bar at the bottom of the
/// link text. Opaque body content, not glass.
public enum MusicLinkToken {
    /// The SF Symbol before the link text.
    public static let glyphSymbolName = "music.note"

    /// The glyph's height as a part of the font's cap height. The glyph sits
    /// on the baseline and stays below the ascender, so the line is no taller.
    public static let glyphHeightScale: CGFloat = 1

    /// The space after the glyph, as a part of the font size.
    public static let glyphTrailingSpaceScale: CGFloat = 0.2

    /// The underline of the link text where the gradient bar does not draw
    /// (the iOS body view). On macOS the bar takes its place.
    public static let underlineStyle = NSUnderlineStyle.single

    /// The color of the link text on iOS, where the underline is the cue. On
    /// macOS the link text has the body text color, and the gradient bar and
    /// the glyph are the cue (MATRIX-187).
    public static var tint: PlatformColor {
        #if canImport(AppKit)
            .linkColor
        #else
            .link
        #endif
    }

    /// The glyph's color in light mode: a darker violet than the bar's first
    /// stop, with a contrast of 4.2:1 on white.
    public static let glyphLightRGB: UInt32 = 0x8B5CF6

    /// The glyph's color in dark mode: the bar's first stop.
    public static let glyphDarkRGB: UInt32 = 0xA78BFA

    /// The color of the glyph: the violet of the bar's first stop, darker in
    /// light mode. It resolves when the glyph draws.
    public static var glyphColor: PlatformColor {
        #if canImport(AppKit)
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(rgb: isDark ? glyphDarkRGB : glyphLightRGB)
            }
        #else
            UIColor { traits in
                UIColor(rgb: traits.userInterfaceStyle == .dark ? glyphDarkRGB : glyphLightRGB)
            }
        #endif
    }

    // MARK: Gradient bar (MATRIX-187)

    /// The height of the bar in points.
    public static let barThickness: CGFloat = 3

    /// The distance from the bottom of the glyphs (the descent) to the
    /// bottom of the bar, as a part of the font size. The bar never goes
    /// below the line, so the line is no taller.
    public static let barDropScale: CGFloat = 0.08

    /// The color stops of the bar, left to right: violet, pink, mint, sky.
    ///
    /// One set for light and dark mode. On the dark timeline background
    /// (about #1E1E1E) the contrast is 6.1:1 (violet) to 9.8:1 (mint), so
    /// no stop needs a dark variant.
    public static var barStops: [(color: PlatformColor, location: CGFloat)] {
        [
            (PlatformColor(rgb: 0xA78BFA), 0),
            (PlatformColor(rgb: 0xF0A6CA), 0.34),
            (PlatformColor(rgb: 0x86D7B5), 0.67),
            (PlatformColor(rgb: 0x7CC9E8), 1),
        ]
    }
}

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif
import Models
import Tokens

/// Marks the music links of a rendered body (MATRIX-178).
///
/// A link that `MusicLink.classify` accepts keeps its text. Its target
/// becomes `MusicLink.songLinkURL`, and a small glyph goes before it. On
/// macOS the link text has the body text color and `.musicLinkMarker` in
/// place of the underline, and `MusicLinkBar` draws the gradient bar under
/// it (MATRIX-187). The glyph and the text carry the target as
/// `.musicLinkTarget`, not `.link`. On iOS the link keeps `.link`, the link
/// tint, and an underline. The glyph is a fixed-size attachment, set from
/// the font alone, so the body has one layout from its first draw.
///
/// The glyph adds width, so a long link can wrap one line later. The row
/// height stays right because the height measure and the drawn row parse
/// the body through the same `FormattedBodyText` with the same switch, so
/// both lay out this one string. A change of the switch measures every row
/// again (`TimelineViewController.handleUserDefaultsChange`).
///
/// This step runs after the cached render, on the copy that
/// `EmoticonResolver` returns, so the `renderHTML` cache key does not hold
/// the switch.
@MainActor
enum MusicLinkMarker {
    static func mark(_ body: NSAttributedString, baseFontSize: CGFloat) -> NSAttributedString {
        var found: [(range: NSRange, link: MusicLink)] = []
        body.enumerateAttribute(.link, in: NSRange(location: 0, length: body.length)) { value, range, _ in
            let link: MusicLink? = switch value {
            case let url as URL: MusicLink.classify(url)
            case let string as String: MusicLink.classify(string)
            default: nil
            }
            if let link {
                found.append((range, link))
            }
        }
        guard !found.isEmpty else { return body }

        let output = NSMutableAttributedString(attributedString: body)
        // Back to front, so an earlier range stays valid after an insert.
        for (range, link) in found.reversed() {
            let attributes = output.attributes(at: range.location, effectiveRange: nil)
            let font = attributes[.font] as? PlatformFont ?? PlatformFont.systemFont(ofSize: baseFontSize)
            #if canImport(AppKit)
                // AppKit draws `.link` text in the link color whatever its
                // `.foregroundColor`. The link text has no `.link` and no color
                // of its own, so it draws as the body text around it. The
                // gradient bar takes the place of the underline (MATRIX-187),
                // and `musicLinkTargets` opens the target on a click.
                output.removeAttribute(.link, range: range)
                output.removeAttribute(.foregroundColor, range: range)
                output.removeAttribute(.underlineStyle, range: range)
                output.addAttributes([.musicLinkMarker: true, .musicLinkTarget: link.songLinkURL], range: range)
            #else
                output.addAttributes([.link: link.songLinkURL, .foregroundColor: MusicLinkToken.tint], range: range)
                output.addAttribute(.underlineStyle, value: MusicLinkToken.underlineStyle.rawValue, range: range)
            #endif

            let glyph = NSMutableAttributedString(attachment: MusicLinkGlyph(font: font))
            var glyphAttributes = attributes
            #if canImport(AppKit)
                glyphAttributes[.link] = nil
                glyphAttributes[.musicLinkTarget] = link.songLinkURL
            #else
                glyphAttributes[.link] = link.songLinkURL
            #endif
            glyphAttributes[.underlineStyle] = nil
            glyphAttributes[.kern] = font.pointSize * MusicLinkToken.glyphTrailingSpaceScale
            glyph.addAttributes(glyphAttributes, range: NSRange(location: 0, length: glyph.length))
            output.insert(glyph, at: range.location)
        }
        return output
    }
}

/// The glyph before a music link: `MusicLinkToken.glyphSymbolName` in
/// `MusicLinkToken.glyphColor`, on the baseline, at the font's cap height.
final class MusicLinkGlyph: NSTextAttachment {
    init(font: PlatformFont) {
        super.init(data: nil, ofType: nil)
        let height = ceil(font.capHeight * MusicLinkToken.glyphHeightScale)
        guard let symbol = Self.symbol(pointSize: font.pointSize) else {
            bounds = .zero
            return
        }
        let width = ceil(symbol.size.width * height / max(symbol.size.height, 1))
        let size = CGSize(width: width, height: height)
        image = Self.tinted(symbol, size: size)
        // On the baseline and below the ascender: the line is no taller.
        bounds = CGRect(origin: .zero, size: size)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("MusicLinkGlyph is never archived")
    }

    private static func symbol(pointSize: CGFloat) -> PlatformImage? {
        #if canImport(AppKit)
            NSImage(systemSymbolName: MusicLinkToken.glyphSymbolName, accessibilityDescription: "Music link")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
        #elseif canImport(UIKit)
            UIImage(
                systemName: MusicLinkToken.glyphSymbolName,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            )
        #endif
    }

    /// The symbol drawn in the glyph color. The color resolves when the
    /// glyph draws, so it follows light and dark mode.
    private static func tinted(_ symbol: PlatformImage, size: CGSize) -> PlatformImage {
        #if canImport(AppKit)
            NSImage(size: size, flipped: false) { rect in
                symbol.draw(in: rect)
                MusicLinkToken.glyphColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        #elseif canImport(UIKit)
            UIGraphicsImageRenderer(size: size).image { _ in
                symbol.withTintColor(MusicLinkToken.glyphColor, renderingMode: .alwaysOriginal)
                    .draw(in: CGRect(origin: .zero, size: size))
            }
        #endif
    }
}

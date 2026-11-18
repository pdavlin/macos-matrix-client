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
/// On macOS, a Spotify link whose text is its URL shows `Artist · Name` in
/// place of the URL when `titles` holds the link's title (MATRIX-191). The
/// glyph and the text then carry `.musicLinkHelp`, "Replaced automatically"
/// and the URL, for the tooltip of the click areas. A link with its own text
/// keeps it. The height measure and the drawn row read the same store, so
/// both lay out the title, and the timeline measures a row again when a
/// title arrives (`MusicLinkTitleStore.titlesDidChange`).
///
/// This step runs after the cached render, on the copy that
/// `EmoticonResolver` returns, so the `renderHTML` cache key does not hold
/// the switch or the titles.
@MainActor
enum MusicLinkMarker {
    static func mark(_ body: NSAttributedString, baseFontSize: CGFloat, titles: MusicLinkTitleStore? = nil) -> NSAttributedString {
        let found = links(in: body)
        guard !found.isEmpty else { return body }

        let output = NSMutableAttributedString(attributedString: body)
        // Back to front, so an earlier range stays valid after an insert.
        for (foundRange, link) in found.reversed() {
            var range = foundRange
            let attributes = output.attributes(at: range.location, effectiveRange: nil)
            let font = attributes[.font] as? PlatformFont ?? PlatformFont.systemFont(ofSize: baseFontSize)
            #if canImport(AppKit)
                let help = titles.flatMap { replaceText(in: output, range: &range, link: link, titles: $0) }
                // AppKit draws `.link` text in the link color whatever its
                // `.foregroundColor`. The link text has no `.link` and no color
                // of its own, so it draws as the body text around it. The
                // gradient bar takes the place of the underline (MATRIX-187),
                // and `musicLinkTargets` opens the target on a click.
                output.removeAttribute(.link, range: range)
                output.removeAttribute(.foregroundColor, range: range)
                output.removeAttribute(.underlineStyle, range: range)
                output.addAttributes([.musicLinkMarker: true, .musicLinkTarget: link.songLinkURL], range: range)
                if let help {
                    output.addAttribute(.musicLinkHelp, value: help, range: range)
                }
            #else
                output.addAttributes([.link: link.songLinkURL, .foregroundColor: MusicLinkToken.tint], range: range)
                output.addAttribute(.underlineStyle, value: MusicLinkToken.underlineStyle.rawValue, range: range)
            #endif

            let glyph = NSMutableAttributedString(attachment: MusicLinkGlyph(font: font))
            var glyphAttributes = attributes
            #if canImport(AppKit)
                glyphAttributes[.link] = nil
                glyphAttributes[.musicLinkTarget] = link.songLinkURL
                glyphAttributes[.musicLinkHelp] = help
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

    #if canImport(AppKit)
        /// Puts the title of `link` in place of the link text in `range`,
        /// and sets `range` to the new text (MATRIX-191). Only for a link
        /// whose text is the link's own URL, and only when `titles` holds a
        /// title.
        ///
        /// - Returns: The tooltip text, or nil when the text stays.
        private static func replaceText(
            in output: NSMutableAttributedString,
            range: inout NSRange,
            link: MusicLink,
            titles: MusicLinkTitleStore
        ) -> String? {
            guard let title = titles.title(for: link) else { return nil }
            let original = linkText(in: output, range: range)
            guard showsOwnURL(original, link: link) else { return nil }
            let text = title.text
            // The new characters take the attributes of the first old one.
            output.replaceCharacters(in: range, with: text)
            range = NSRange(location: range.location, length: (text as NSString).length)
            return "Replaced automatically\n\(original)"
        }
    #endif

    /// The music links of a rendered body (`.link` targets that
    /// `MusicLink.classify` accepts), in order.
    static func links(in body: NSAttributedString) -> [(range: NSRange, link: MusicLink)] {
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
        return found
    }

    /// The Spotify links of a rendered body whose text is their own URL:
    /// the links that show a title when the store holds one (MATRIX-191).
    static func titleCandidates(in body: NSAttributedString) -> [MusicLink] {
        links(in: body).compactMap { range, link in
            link.service == .spotify && showsOwnURL(linkText(in: body, range: range), link: link) ? link : nil
        }
    }

    private static func linkText(in body: NSAttributedString, range: NSRange) -> String {
        (body.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True if `text` is a URL of the same song or album as `link`.
    private static func showsOwnURL(_ text: String, link: MusicLink) -> Bool {
        MusicLink.classify(text)?.canonicalURL == link.canonicalURL
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

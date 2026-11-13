#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif
import SwiftUI
import Tokens
import UI

/// A custom emoticon in a message body (MATRIX-153).
///
/// The bounds are a square at the line height of the font around it, set
/// when the body is parsed. They do not depend on the image, so the body
/// lays out the same before and after the image loads, and the row height
/// the timeline measured stays right. The square draws the image when the
/// loader's cache has it, and the alt text (`:name:`) when it does not.
final class EmoticonAttachment: NSTextAttachment {
    /// The `mxc://` source.
    let source: String
    /// The alt text, for example `:partyparrot:`.
    let alt: String
    /// True when the attachment draws the image, false when it draws `alt`.
    let isLoaded: Bool

    init(source: String, alt: String, font: PlatformFont, picture: PlatformImage?) {
        self.source = source
        self.alt = alt
        isLoaded = picture != nil
        super.init(data: nil, ofType: nil)

        let side = Self.side(for: font)
        image = picture ?? Self.altImage(alt, side: side)
        // The square sits on the descender line, so it covers the font's own
        // line box and never makes the line taller.
        bounds = CGRect(x: 0, y: font.descender, width: side, height: side)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("EmoticonAttachment is never archived")
    }

    /// The side of the square: the font's line height, rounded down.
    static func side(for font: PlatformFont) -> CGFloat {
        floor(font.ascender - font.descender)
    }

    /// The alt text, drawn inside the square. A long name gets a smaller
    /// font, down to a floor, and then a truncated tail.
    private static func altImage(_ alt: String, side: CGFloat) -> PlatformImage {
        let size = CGSize(width: side, height: side)
        #if canImport(AppKit)
            return NSImage(size: size, flipped: false) { rect in
                drawAlt(alt, in: rect, color: .secondaryLabelColor)
                return true
            }
        #elseif canImport(UIKit)
            return UIGraphicsImageRenderer(size: size).image { _ in
                drawAlt(alt, in: CGRect(origin: .zero, size: size), color: .secondaryLabel)
            }
        #endif
    }

    private static func drawAlt(_ alt: String, in rect: CGRect, color: PlatformColor) {
        let text = alt as NSString
        let largest = rect.height * 0.6
        let smallest = rect.height * 0.36
        let naturalWidth = text.size(withAttributes: [.font: PlatformFont.systemFont(ofSize: largest)]).width
        let fontSize = naturalWidth > rect.width ? max(smallest, largest * rect.width / naturalWidth) : largest
        let font = PlatformFont.systemFont(ofSize: fontSize)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let lineHeight = ceil(font.ascender - font.descender)
        let line = CGRect(x: rect.minX, y: rect.midY - lineHeight / 2, width: rect.width, height: lineHeight)
        text.draw(
            with: line,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph],
            context: nil
        )
    }
}

/// Swaps the ranges `ImageTagRewriter` marked for emoticon attachments.
@MainActor
enum EmoticonResolver {
    /// The pixel scale the cached image is drawn at for the attachment. A
    /// constant, not the screen's scale, so a render is the same on every
    /// display.
    #if canImport(AppKit)
        private static let renderScale: CGFloat = 2
    #else
        private static let renderScale: CGFloat = 3
    #endif

    /// - Parameters:
    ///   - rendered: the renderer's output for `ImageTagRewriter`'s HTML.
    ///   - sources: the emoticon sources, in document order.
    ///   - baseFontSize: the body font size, for a range with no font.
    ///   - imageLoader: the app's image loader. Only its cache is read here.
    static func resolve(
        _ rendered: NSAttributedString,
        sources: [String],
        baseFontSize: CGFloat,
        imageLoader: (any ImageLoader)?
    ) -> NSAttributedString {
        let output = NSMutableAttributedString(attributedString: rendered)
        let ranges = markedRanges(in: output.string as NSString)
        guard !ranges.isEmpty, ranges.count == sources.count else {
            // The renderer dropped or split a marker. Keep the alt text.
            return strippingMarkers(output)
        }

        // Back to front, so an earlier range stays valid.
        for (index, range) in ranges.enumerated().reversed() {
            let text = output.string as NSString
            let alt = text.substring(with: NSRange(location: range.location + 1, length: range.length - 2))
            let attributes = output.attributes(at: range.location, effectiveRange: nil)
            let font = attributes[.font] as? PlatformFont ?? PlatformFont.systemFont(ofSize: baseFontSize)
            let source = sources[index]

            let picture = imageLoader?.cachedImage(matrixUrl: source).flatMap {
                platformImage(from: $0, side: EmoticonAttachment.side(for: font))
            }
            let attachment = EmoticonAttachment(source: source, alt: alt, font: font, picture: picture)
            let replacement = NSMutableAttributedString(attachment: attachment)
            replacement.addAttributes(attributes, range: NSRange(location: 0, length: replacement.length))
            output.replaceCharacters(in: range, with: replacement)
        }
        // A marker with no partner, if any, must not reach the screen.
        return strippingMarkers(output)
    }

    /// Each `open … close` range, markers included, in document order.
    private static func markedRanges(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var cursor = 0
        while cursor < text.length {
            let open = text.range(of: ImageTagRewriter.openMarker, range: NSRange(location: cursor, length: text.length - cursor))
            guard open.location != NSNotFound else { break }
            let afterOpen = open.location + open.length
            let close = text.range(of: ImageTagRewriter.closeMarker, range: NSRange(location: afterOpen, length: text.length - afterOpen))
            guard close.location != NSNotFound else { break }
            cursor = close.location + close.length
            ranges.append(NSRange(location: open.location, length: cursor - open.location))
        }
        return ranges
    }

    private static func strippingMarkers(_ string: NSMutableAttributedString) -> NSAttributedString {
        for marker in [ImageTagRewriter.openMarker, ImageTagRewriter.closeMarker] {
            string.mutableString.replaceOccurrences(
                of: marker,
                with: "",
                range: NSRange(location: 0, length: string.length)
            )
        }
        return string
    }

    /// The loader hands out SwiftUI images. This draws one into the square,
    /// aspect-fit, as the platform image a text attachment needs.
    private static func platformImage(from image: Image, side: CGFloat) -> PlatformImage? {
        let renderer = ImageRenderer(
            content: image
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: side, height: side)
        )
        renderer.scale = renderScale
        #if canImport(AppKit)
            return renderer.nsImage
        #elseif canImport(UIKit)
            return renderer.uiImage
        #endif
    }
}

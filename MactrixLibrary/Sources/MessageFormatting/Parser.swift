#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif
import Foundation
import Models
import Tokens
import UI
import ZMarkupParser

/// Renders a message's HTML body.
///
/// `<img>` never reaches the HTML renderer (MATRIX-153). A custom emoticon
/// (an `mxc://` source with `data-mx-emoticon` or a `:name:` alt or title,
/// see `ImageTagRewriter`) becomes a fixed-size inline
/// attachment that draws from `imageLoader`'s cache, or its alt text when the
/// cache has no image. Every other `<img>` becomes its alt text. This
/// function starts no load; `FormattedBodyText` does that.
///
/// With `marksMusicLinks`, a link to a song or an album on a music service
/// that is not Apple Music gets the music link marker and the song.link
/// target (MATRIX-178, `MusicLinkMarker`). The step runs after the cached
/// render, so the cache key does not hold the switch. On macOS, a Spotify
/// link that shows its URL shows its title from `musicLinkTitles` in place of
/// the URL when the store holds one (MATRIX-191).
@MainActor
public func parseFormattedBody(
    _ body: String,
    baseFontSize: CGFloat? = nil,
    imageLoader: (any ImageLoader)? = nil,
    marksMusicLinks: Bool = false,
    musicLinkTitles: MusicLinkTitleStore? = nil
) -> NSAttributedString {
    let baseFontSize = baseFontSize ?? CGFloat(TypographyToken.defaultBaseFontSize)
    let rewritten = ImageTagRewriter.rewrite(body)
    let resolved = EmoticonResolver.resolve(
        renderHTML(rewritten.html, baseFontSize: baseFontSize),
        sources: rewritten.emoticonSources,
        baseFontSize: baseFontSize,
        imageLoader: imageLoader
    )
    guard marksMusicLinks else { return resolved }
    return MusicLinkMarker.mark(resolved, baseFontSize: baseFontSize, titles: musicLinkTitles)
}

/// The Spotify links of an HTML body whose text is their own URL: the links
/// that can show a title (MATRIX-191). Reads the cached render.
@MainActor
func musicLinkTitleCandidates(inFormattedBody body: String, baseFontSize: CGFloat) -> [MusicLink] {
    MusicLinkMarker.titleCandidates(in: renderHTML(ImageTagRewriter.rewrite(body).html, baseFontSize: baseFontSize))
}

/// One custom emoticon of a message body (MATRIX-161).
public struct BodyEmoticon: Equatable, Sendable {
    /// The tag's alt, else its title, as the sender wrote it: for a bridge
    /// emoticon, `:name:`. Can be empty.
    public let name: String
    /// The `mxc://` source.
    public let source: String

    public init(name: String, source: String) {
        self.name = name
        self.source = source
    }
}

/// The custom emoticons in an HTML body, in document order. A source that
/// occurs twice counts once, with its first name.
public func emoticons(inFormattedBody body: String) -> [BodyEmoticon] {
    let rewritten = ImageTagRewriter.rewrite(body)
    var seen = Set<String>()
    return zip(rewritten.emoticonNames, rewritten.emoticonSources).compactMap { name, source in
        seen.insert(source).inserted ? BodyEmoticon(name: name, source: source) : nil
    }
}

/// The `mxc://` sources of the custom emoticons in an HTML body, in document
/// order, without duplicates.
public func emoticonSources(inFormattedBody body: String) -> [String] {
    emoticons(inFormattedBody: body).map(\.source)
}

/// The renders of `renderHTML`, by font size and body (MATRIX-174).
///
/// A render is a function of these two alone, and it costs 0.3 to 1.5 ms. A
/// row asks for the same render at least twice (the height measure, then the
/// row itself), and again each time SwiftUI evaluates the body view. The
/// cache holds immutable copies; `EmoticonResolver` copies before it edits.
@MainActor private let renderedBodies: NSCache<NSString, NSAttributedString> = {
    let cache = NSCache<NSString, NSAttributedString>()
    cache.countLimit = 512
    return cache
}()

/// The ZMarkupParser step. Internal so a test can hand it a raw `<img>` and
/// prove that the renderer by itself makes no image attachment.
@MainActor
func renderHTML(_ body: String, baseFontSize: CGFloat) -> NSAttributedString {
    let key = "\(baseFontSize)\u{0}\(body)" as NSString
    if let cached = renderedBodies.object(forKey: key) {
        return cached
    }
    let rendered = NSAttributedString(attributedString: buildHTML(body, baseFontSize: baseFontSize))
    renderedBodies.setObject(rendered, forKey: key)
    return rendered
}

/// Builds the parser and renders `body`. `renderHTML` caches the result.
@MainActor
private func buildHTML(_ body: String, baseFontSize: CGFloat) -> NSAttributedString {
    let headingParagraphSpacing = MarkupStyleParagraphStyle(
        // paragraphSpacing: 5,
        paragraphSpacingBefore: baseFontSize * TypographyToken.paragraphSpacingBeforeScale
    )

    let parser = ZHTMLParserBuilder
        .initWithDefault()
        // Replaces the default `IMG_HTMLTagName`, whose attachment downloads
        // `src` with `URLSession.shared`. `ImageTagRewriter` removes every
        // well-formed `<img>` first; this covers a tag it could not read.
        .add(ExtendTagName("img"))
        .set(rootStyle: MarkupStyle(font: MarkupStyleFont(size: baseFontSize)))
        .add(
            H1_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(size: baseFontSize * TypographyToken.heading1Scale),
                paragraphStyle: headingParagraphSpacing
            )
        )
        .add(
            H2_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(size: baseFontSize * TypographyToken.heading2Scale),
                paragraphStyle: headingParagraphSpacing
            )
        )
        .add(
            H3_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(size: baseFontSize * TypographyToken.heading3Scale),
                paragraphStyle: headingParagraphSpacing
            )
        )
        .add(
            H4_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(size: baseFontSize * TypographyToken.heading4Scale, weight: .style(.medium)),
                paragraphStyle: headingParagraphSpacing
            )
        )
        .add(
            H5_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(size: baseFontSize * TypographyToken.bodyScale, weight: .style(.semibold)),
                paragraphStyle: headingParagraphSpacing
            )
        )
        .add(
            H6_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(size: baseFontSize * TypographyToken.bodyScale, weight: .style(.semibold)),
                paragraphStyle: headingParagraphSpacing
            )
        )
        .add(
            P_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                paragraphStyle: MarkupStyleParagraphStyle(
                    paragraphSpacing: baseFontSize * TypographyToken.paragraphSpacingScale,
                    paragraphSpacingBefore: baseFontSize * TypographyToken.paragraphSpacingScale
                )
            )
        )
        // MATRIX-192: the parser's default quote is a 10 pt indent alone.
        .add(
            BLOCKQUOTE_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                paragraphStyle: MarkupStyleParagraphStyle(
                    headIndent: baseFontSize * BlockQuoteToken.indentScale,
                    firstLineHeadIndent: baseFontSize * BlockQuoteToken.indentScale
                ),
                foregroundColor: MarkupStyleColor(color: BlockQuoteToken.textColor)
            )
        )
        // MATRIX-202: the installed code family. The parser applies bold and
        // italic by family and traits, so they get the family's own faces.
        .add(
            CODE_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(
                    size: baseFontSize * TypographyToken.bodyScale,
                    familyName: TypographyToken.installedCodeFontFamily.map { .familyNames([$0]) }
                )
                // backgroundColor: .init(color: NSColor(red: 0.8, green: 0.8, blue: 1, alpha: 0.5))
            )
        )
        .build()

    return parser.render(body)
}

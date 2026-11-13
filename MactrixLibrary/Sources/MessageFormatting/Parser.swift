#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif
import Foundation
import Tokens
import UI
import ZMarkupParser

/// Renders a message's HTML body.
///
/// `<img>` never reaches the HTML renderer (MATRIX-153). A custom emoticon
/// (`data-mx-emoticon` with an `mxc://` source) becomes a fixed-size inline
/// attachment that draws from `imageLoader`'s cache, or its alt text when the
/// cache has no image. Every other `<img>` becomes its alt text. This
/// function starts no load; `FormattedBodyText` does that.
@MainActor
public func parseFormattedBody(
    _ body: String,
    baseFontSize: CGFloat? = nil,
    imageLoader: (any ImageLoader)? = nil
) -> NSAttributedString {
    let baseFontSize = baseFontSize ?? CGFloat(TypographyToken.defaultBaseFontSize)
    let rewritten = ImageTagRewriter.rewrite(body)
    return EmoticonResolver.resolve(
        renderHTML(rewritten.html, baseFontSize: baseFontSize),
        sources: rewritten.emoticonSources,
        baseFontSize: baseFontSize,
        imageLoader: imageLoader
    )
}

/// The `mxc://` sources of the custom emoticons in an HTML body, in document
/// order, without duplicates.
public func emoticonSources(inFormattedBody body: String) -> [String] {
    var seen = Set<String>()
    return ImageTagRewriter.rewrite(body).emoticonSources.filter { seen.insert($0).inserted }
}

/// The ZMarkupParser step. Internal so a test can hand it a raw `<img>` and
/// prove that the renderer by itself makes no image attachment.
@MainActor
func renderHTML(_ body: String, baseFontSize: CGFloat) -> NSAttributedString {
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
        .add(
            CODE_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(size: baseFontSize * TypographyToken.bodyScale, familyName: .familyNames(["Menlo"]))
                // backgroundColor: .init(color: NSColor(red: 0.8, green: 0.8, blue: 1, alpha: 0.5))
            )
        )
        .build()

    return parser.render(body)
}

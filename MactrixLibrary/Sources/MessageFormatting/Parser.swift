import AppKit
import Foundation
import Tokens
import ZMarkupParser

@MainActor
public func parseFormattedBody(_ body: String, baseFontSize: CGFloat? = nil) -> NSAttributedString {
    let baseFontSize = baseFontSize ?? CGFloat(TypographyToken.defaultBaseFontSize)
    let headingParagraphSpacing = MarkupStyleParagraphStyle(
        // paragraphSpacing: 5,
        paragraphSpacingBefore: baseFontSize * TypographyToken.paragraphSpacingBeforeScale
    )

    let parser = ZHTMLParserBuilder
        .initWithDefault()
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

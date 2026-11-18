import AppKit
@testable import MessageFormatting
import SwiftUI
import Testing
import Tokens

/// MATRIX-192: a body with a block quote shows all of its lines.
///
/// A Slack message `>30 FPS`, a blank line, `unplayable` showed one line, and
/// the body scrolled inside its row. The label cell leaves a paragraph's head
/// indent out of the width it measures when one paragraph style covers the
/// whole string, as a block quote's does. The field then got that width, and
/// at that width its indented lines wrapped again: the field held fewer lines
/// than it drew.
///
/// The exact HTML that mautrix-slack sends is not known, so the reported case
/// is tested in the forms a bridge can send.
@MainActor
struct BlockQuoteBodyTests {
    nonisolated static let width: CGFloat = 300

    enum Body: String, CaseIterable, CustomTestStringConvertible {
        /// The reported case: the quote and the text after it in one quote.
        case reportedAllQuoted
        /// The reported case: the quote, then a line break and the text.
        case reportedQuoteThenBreak
        /// The reported case: the quote, then the text with no break.
        case reportedQuoteThenText
        /// The reported case in Markdown paragraphs.
        case reportedQuoteThenParagraph
        case quoteAlone
        case multiLineQuote
        case nestedQuote
        case quoteWithLink

        var testDescription: String { rawValue }

        var html: String {
            switch self {
            case .reportedAllQuoted: "<blockquote>30 FPS<br><br>unplayable</blockquote>"
            case .reportedQuoteThenBreak: "<blockquote>30 FPS</blockquote><br>unplayable"
            case .reportedQuoteThenText: "<blockquote>30 FPS</blockquote>unplayable"
            case .reportedQuoteThenParagraph: "<blockquote>\n<p>30 FPS</p>\n</blockquote>\n<p>unplayable</p>\n"
            case .quoteAlone: "<blockquote>30 FPS</blockquote>"
            case .multiLineQuote: "<blockquote>the first line<br>the second line<br>the third line</blockquote>"
            case .nestedQuote: "<blockquote><blockquote>the inner quote</blockquote>the outer quote</blockquote>"
            case .quoteWithLink: #"<blockquote>see <a href="https://example.org/a/page">this page</a> first</blockquote>"#
            }
        }

        /// The lines the body has at the test width: no line wraps.
        var lines: Int {
            switch self {
            case .reportedAllQuoted, .reportedQuoteThenBreak, .multiLineQuote: 3
            case .reportedQuoteThenText, .reportedQuoteThenParagraph, .nestedQuote: 2
            case .quoteAlone, .quoteWithLink: 1
            }
        }
    }

    /// The body hosted at the test width, laid out as the timeline lays out a body.
    private func hosted(_ html: String) -> NSHostingController<AnyView> {
        let view = FormattedBodyText(html: html, baseFontSize: 13, imageLoader: nil)
        let controller = NSHostingController(
            rootView: AnyView(view.fixedSize(horizontal: false, vertical: true).frame(width: Self.width, alignment: .leading))
        )
        controller.view.appearance = NSAppearance(named: .aqua)
        controller.view.frame.size = controller.view.fittingSize
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    private static func field(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        for subview in view.subviews {
            if let field = field(in: subview) { return field }
        }
        return nil
    }

    /// The height of one line of the body font.
    private static var lineHeight: CGFloat {
        NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: 13))
    }

    /// The field is as tall as the expected lines, and it holds every line
    /// that the label cell lays out at the field's own width.
    @Test(arguments: Body.allCases)
    func theFieldHoldsEveryLine(body: Body) throws {
        let controller = hosted(body.html)
        let field = try #require(Self.field(in: controller.view))
        let frame = field.frame

        #expect(frame.height >= CGFloat(body.lines) * Self.lineHeight - 0.5)

        let cell = try #require(field.cell)
        let drawn = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: frame.width, height: .greatestFiniteMagnitude))
        #expect(drawn.height <= frame.height + 0.5, "the field draws \(drawn.height) pt of text in \(frame.height) pt")
        #expect(controller.view.fittingSize.height >= frame.height - 0.5)
    }

    /// The measure of `AttributedTextView` gives a width at which the label
    /// cell lays out the measured height, and the same size when it is asked
    /// again at that width.
    @Test(arguments: Body.allCases)
    func theMeasuredWidthHoldsTheMeasuredHeight(body: Body) throws {
        let view = AttributedTextView(attributedString: parseFormattedBody(body.html, baseFontSize: 13))
        let field = LinkCursorTextField(labelWithAttributedString: view.attributedString)
        field.lineBreakMode = .byWordWrapping
        field.usesSingleLineMode = false
        let cell = try #require(field.cell)

        let size = try #require(AttributedTextView.fittingSize(of: field, width: Self.width))
        #expect(size.height >= CGFloat(body.lines) * Self.lineHeight - 0.5)
        let atOwnWidth = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: size.width, height: .greatestFiniteMagnitude))
        #expect(ceil(atOwnWidth.height) <= size.height)

        let again = try #require(AttributedTextView.fittingSize(of: field, width: size.width))
        #expect(again == size)
    }

    /// The quote text indents by the token's part of the font size and has
    /// the token's color. The text after the quote does not. A link in a
    /// quote stays a link.
    @Test func theQuoteHasTheTokenIndentAndColor() throws {
        let string = parseFormattedBody(Body.reportedQuoteThenText.html, baseFontSize: 13)
        let text = string.string as NSString
        let quote = text.range(of: "30 FPS")
        let after = text.range(of: "unplayable")
        let style = try #require(string.attribute(.paragraphStyle, at: quote.location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.headIndent == 13 * BlockQuoteToken.indentScale)
        #expect(style.firstLineHeadIndent == 13 * BlockQuoteToken.indentScale)
        #expect(string.attribute(.foregroundColor, at: quote.location, effectiveRange: nil) as? NSColor == BlockQuoteToken.textColor)
        #expect(string.attribute(.foregroundColor, at: after.location, effectiveRange: nil) == nil)
        #expect((string.attribute(.paragraphStyle, at: after.location, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0 == 0)

        let linked = parseFormattedBody(Body.quoteWithLink.html, baseFontSize: 13)
        let link = (linked.string as NSString).range(of: "this page")
        #expect(linked.attribute(.link, at: link.location, effectiveRange: nil) != nil)
    }

    /// A body with no quote keeps the width of its text.
    @Test func aBodyWithNoIndentKeepsTheWidthOfItsText() throws {
        let view = AttributedTextView(attributedString: parseFormattedBody("<p>a short line</p>", baseFontSize: 13))
        let field = LinkCursorTextField(labelWithAttributedString: view.attributedString)
        let cell = try #require(field.cell)
        let size = try #require(AttributedTextView.fittingSize(of: field, width: Self.width))
        let text = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: Self.width, height: .greatestFiniteMagnitude))
        #expect(size.width == ceil(text.width))
    }
}

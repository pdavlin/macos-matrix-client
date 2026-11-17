import AppKit
@testable import MessageFormatting
import Models
import SwiftUI
import Testing
import Tokens
import UI

/// MATRIX-178: the music link marker in a message body.
///
/// The row height rule (MATRIX-153): the timeline measures a row by laying
/// out the same `FormattedBodyText` that draws it. These tests prove that
/// the view lays out the marked string, glyph included, so the measure and
/// the drawn row agree, also where the glyph moves a wrap.
@MainActor
struct MusicLinkMarkerTests {
    static let trackId = "4cOdK2wGLETKBW3PvgPWqT"
    static let posted = "https://open.spotify.com/track/\(trackId)?si=0123456789abcdef"
    static let target = "https://song.link/https://open.spotify.com/track/\(trackId)"
    static let html = #"<p>listen to <a href="\#(posted)">this song</a> now</p>"#

    private func attachments(in string: NSAttributedString) -> [NSTextAttachment] {
        var found: [NSTextAttachment] = []
        string.enumerateAttribute(.attachment, in: NSRange(location: 0, length: string.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment {
                found.append(attachment)
            }
        }
        return found
    }

    /// The link targets in `string`, as strings, in order.
    private func links(in string: NSAttributedString) -> [String] {
        var found: [String] = []
        string.enumerateAttribute(.link, in: NSRange(location: 0, length: string.length)) { value, _, _ in
            switch value {
            case let url as URL: found.append(url.absoluteString)
            case let text as String: found.append(text)
            default: break
            }
        }
        return found
    }

    /// The height `AttributedTextView.sizeThatFits` gives.
    private func height(of string: NSAttributedString, width: CGFloat) -> CGFloat {
        let field = NSTextField(labelWithAttributedString: string)
        field.lineBreakMode = .byWordWrapping
        field.usesSingleLineMode = false
        field.preferredMaxLayoutWidth = width
        let bounds = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)
        return ceil(field.cell?.cellSize(forBounds: bounds).height ?? 0)
    }

    private static func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        for subview in view.subviews {
            if let field = textField(in: subview) { return field }
        }
        return nil
    }

    /// The body view as the timeline lays it out, at a fixed width.
    private func hosted(_ html: String, width: CGFloat, marksMusicLinks: Bool) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                FormattedBodyText(html: html, baseFontSize: 13, imageLoader: nil, marksMusicLinks: marksMusicLinks)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: width)
            )
        )
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    // MARK: Marker

    @Test func aSongLinkKeepsItsTextAndOpensOnSongLink() throws {
        let marked = parseFormattedBody(Self.html, baseFontSize: 13, marksMusicLinks: true)
        #expect(marked.string.trimmingCharacters(in: .whitespacesAndNewlines) == "listen to \u{FFFC}this song now")
        #expect(links(in: marked) == [Self.target])

        let glyph = try #require(attachments(in: marked).first as? MusicLinkGlyph)
        let font = NSFont.systemFont(ofSize: 13)
        #expect(glyph.bounds.minY == 0)
        #expect(glyph.bounds.height > 0)
        #expect(glyph.bounds.height <= font.ascender)

        let text = marked.string as NSString
        let linkText = text.range(of: "this song")
        let underline = marked.attribute(.underlineStyle, at: linkText.location, effectiveRange: nil) as? Int
        #expect(underline == NSUnderlineStyle.single.rawValue)
        // The glyph carries the target too, and no underline.
        let glyphIndex = text.range(of: "\u{FFFC}").location
        #expect(marked.attribute(.link, at: glyphIndex, effectiveRange: nil) as? URL == URL(string: Self.target))
        #expect(marked.attribute(.underlineStyle, at: glyphIndex, effectiveRange: nil) == nil)
    }

    @Test func otherLinksAndTheSwitchOffStayAsTheyAre() {
        let html = #"<p><a href="https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M">list</a> "#
            + #"<a href="https://spotify.link/AbCdEfGhIjK">short</a> "#
            + #"<a href="https://music.apple.com/us/album/x/1559885420?i=1559885421">apple</a> "#
            + #"<a href="https://example.org">site</a></p>"#
        let marked = parseFormattedBody(html, baseFontSize: 13, marksMusicLinks: true)
        let plain = parseFormattedBody(html, baseFontSize: 13)
        #expect(marked.string == plain.string)
        #expect(attachments(in: marked).isEmpty)
        #expect(links(in: marked) == links(in: plain))

        let off = parseFormattedBody(Self.html, baseFontSize: 13, marksMusicLinks: false)
        #expect(attachments(in: off).isEmpty)
        #expect(links(in: off).allSatisfy { $0.hasPrefix("https://open.spotify.com/track/") })
    }

    /// The marker edits a copy: the cached render keeps the posted link.
    @Test func theCachedRenderKeepsThePostedLink() {
        _ = parseFormattedBody(Self.html, baseFontSize: 13, marksMusicLinks: true)
        let cached = renderHTML(Self.html, baseFontSize: 13)
        #expect(attachments(in: cached).isEmpty)
        #expect(links(in: cached).allSatisfy { $0.hasPrefix("https://open.spotify.com/track/") })
        // And the second marked parse is the same as the first.
        let first = parseFormattedBody(Self.html, baseFontSize: 13, marksMusicLinks: true)
        let second = parseFormattedBody(Self.html, baseFontSize: 13, marksMusicLinks: true)
        #expect(first.string == second.string)
        #expect(links(in: second) == [Self.target])
    }

    /// The glyph sits inside the line: a one-line body is no taller.
    @Test(arguments: [CGFloat(11), 13, 15, 20])
    func aOneLineBodyIsNoTaller(fontSize: CGFloat) {
        let marked = parseFormattedBody(Self.html, baseFontSize: fontSize, marksMusicLinks: true)
        let plain = parseFormattedBody(Self.html, baseFontSize: fontSize)
        #expect(height(of: marked, width: 400) == height(of: plain, width: 400))
    }

    // MARK: Row height

    /// The view draws the marked string, so the timeline's measure of the
    /// view is the height of that string.
    @Test func theViewLaysOutTheMarkedString() throws {
        let controller = hosted(Self.html, width: 300, marksMusicLinks: true)
        let field = try #require(Self.textField(in: controller.view))
        let expected = AttributedTextView(attributedString: parseFormattedBody(Self.html, baseFontSize: 13, marksMusicLinks: true))
            .attributedString
        #expect(field.attributedStringValue.string == expected.string)
        #expect(links(in: field.attributedStringValue) == links(in: expected))
        #expect(attachments(in: field.attributedStringValue).count == 1)
        #expect(controller.view.fittingSize.height == height(of: expected, width: 300))
    }

    /// A long link where the glyph moves the wrap: at this width the plain
    /// string takes one line and the marked string two. The view, measured
    /// as the timeline measures a row, has the marked string's height.
    @Test func theMeasureFollowsTheGlyphWhenItMovesAWrap() throws {
        let html = #"<a href="\#(Self.posted)">\#(Self.posted)</a>"#
        let marked = parseFormattedBody(html, baseFontSize: 13, marksMusicLinks: true)
        let plain = parseFormattedBody(html, baseFontSize: 13)

        let start = Int(ceil(plain.size().width))
        let width = try #require((start ... start + 40).map { CGFloat($0) }.first {
            height(of: marked, width: $0) > height(of: plain, width: $0)
        })

        let markedController = hosted(html, width: width, marksMusicLinks: true)
        let plainController = hosted(html, width: width, marksMusicLinks: false)
        #expect(markedController.view.fittingSize.height == height(of: marked, width: width))
        #expect(plainController.view.fittingSize.height == height(of: plain, width: width))
        #expect(markedController.view.fittingSize.height > plainController.view.fittingSize.height)
    }
}

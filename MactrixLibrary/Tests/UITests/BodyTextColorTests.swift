import AppKit
@testable import MessageFormatting
import SwiftUI
import Testing
import Tokens

/// MATRIX-204: a message body stays readable in dark mode after a click on
/// its text.
///
/// A click on the text of a body starts the field editor of its
/// `LinkCursorTextField`. The label draws a run with no `.foregroundColor` in
/// its own text color, but the field editor draws that run in black. So each
/// run of the body's string must carry a color, and each color must resolve
/// at draw time (a dynamic color), so that it follows the appearance.
@MainActor
struct BodyTextColorTests {
    nonisolated static let spotify = "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"

    enum Body: String, CaseIterable {
        case plain, formatted, link, mention, quote, code, emoji, musicLink

        var html: String {
            switch self {
            case .plain: "just some words"
            case .formatted: "<p>plain <b>bold</b> <i>italic</i></p><h3>heading</h3><ul><li>item</li></ul>"
            case .link: #"<p>see <a href="https://example.org/page">this page</a> now</p>"#
            case .mention: #"<p>hi <a href="https://matrix.to/#/@alice:example.org">Alice</a> there</p>"#
            case .quote: "<blockquote>quoted words</blockquote><p>the reply</p>"
            case .code: "<p>run <code>make test</code> please</p><pre><code>let x = 1</code></pre>"
            case .emoji: "<p>nice 🎉 one</p>"
            case .musicLink: #"<p>listen to <a href="\#(BodyTextColorTests.spotify)">this song</a> now</p>"#
            }
        }
    }

    /// The string the body's field shows, as `FormattedBodyText` builds it.
    private func fieldString(_ body: Body) -> NSAttributedString {
        AttributedTextView(attributedString: parseFormattedBody(body.html, baseFontSize: 13, marksMusicLinks: true)).attributedString
    }

    private static func resolved(_ color: NSColor, in name: NSAppearance.Name) -> NSColor? {
        var output: NSColor?
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            output = color.usingColorSpace(.sRGB)
        }
        return output
    }

    private static func field(in view: NSView) -> LinkCursorTextField? {
        if let field = view as? LinkCursorTextField { return field }
        for subview in view.subviews {
            if let field = field(in: subview) { return field }
        }
        return nil
    }

    // MARK: The string

    /// Every run has a color. Each color resolves to another value in dark
    /// mode than in light mode, so it was not resolved once and stored, and
    /// in dark mode it is light enough to read.
    @Test(arguments: Body.allCases)
    func everyRunHasADynamicColor(body: Body) throws {
        let string = fieldString(body)
        #expect(string.length > 0)
        var colors: [NSColor] = []
        string.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: string.length)) { value, range, _ in
            let color = value as? NSColor
            #expect(color != nil, "run \(range) of \(body.rawValue) has no color")
            if let color { colors.append(color) }
        }
        for color in colors {
            let light = try #require(Self.resolved(color, in: .aqua))
            let dark = try #require(Self.resolved(color, in: .darkAqua))
            #expect(light != dark, "\(color) does not follow the appearance")
            #expect(dark.brightnessComponent > 0.6)
        }
    }

    /// The colors set on purpose stay: a link and a mention keep the
    /// parser's link color, a quote the secondary color (MATRIX-192). Plain
    /// text, code and a marked music link (MATRIX-187) get the label color.
    @Test func theColorsSetOnPurposeStay() {
        func color(_ body: Body, at text: String) -> NSColor? {
            let string = fieldString(body)
            let index = (string.string as NSString).range(of: text).location
            return string.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
        }
        let parsedLink = parseFormattedBody(Body.link.html, baseFontSize: 13)
        let linkIndex = (parsedLink.string as NSString).range(of: "this page").location
        #expect(color(.plain, at: "words") == NSColor.labelColor)
        #expect(color(.link, at: "see") == NSColor.labelColor)
        #expect(color(.link, at: "this page") != nil)
        #expect(color(.link, at: "this page") == parsedLink.attribute(.foregroundColor, at: linkIndex, effectiveRange: nil) as? NSColor)
        #expect(color(.mention, at: "Alice") != NSColor.labelColor)
        #expect(color(.quote, at: "quoted") == BlockQuoteToken.textColor)
        #expect(color(.quote, at: "reply") == NSColor.labelColor)
        #expect(color(.musicLink, at: "this song") == NSColor.labelColor)
        #expect(color(.code, at: "make") == NSColor.labelColor)
    }

    /// A string with a color on every run comes back as it is.
    @Test func aStringWithEveryColorSetDoesNotChange() {
        let string = NSAttributedString(string: "red", attributes: [.foregroundColor: NSColor.systemRed])
        #expect(string.withBodyTextColor === string)
    }

    // MARK: The field editor

    /// The body hosted in a dark window, with its field editor started as a
    /// click on the text starts it.
    private func editedBody(_ body: Body) throws -> (field: LinkCursorTextField, editor: NSTextView, window: NSWindow) {
        let view = FormattedBodyText(html: body.html, baseFontSize: 13, imageLoader: nil, marksMusicLinks: true)
        let controller = NSHostingController(
            rootView: AnyView(view.fixedSize(horizontal: false, vertical: true).frame(width: 300, alignment: .leading))
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        let field = try #require(Self.field(in: controller.view))
        field.selectText(nil)
        let editor = try #require(field.currentEditor() as? NSTextView)
        // `selectText` selects all. A click puts the insertion point with no
        // selection, and no selection color then draws over the text.
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        return (field, editor, window)
    }

    /// In the field editor every run keeps a color, so no run falls back to
    /// the editor's black.
    @Test(arguments: Body.allCases)
    func theFieldEditorHasAColorOnEveryRun(body: Body) throws {
        let (_, editor, window) = try editedBody(body)
        defer { window.close() }
        let storage = try #require(editor.textStorage)
        #expect(storage.length > 0)
        storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            #expect(value is NSColor, "run \(range) of \(body.rawValue) has no color in the field editor")
        }
    }

    /// The text that the field editor draws in dark mode is light: the
    /// brightest ink pixel of the field is near white.
    @Test func theFieldEditorDrawsLightTextInDarkMode() throws {
        let (field, _, window) = try editedBody(.plain)
        defer { window.close() }
        #expect(field.bounds.width > 20)
        let rep = try #require(field.bitmapImageRepForCachingDisplay(in: field.bounds))
        field.cacheDisplay(in: field.bounds, to: rep)
        var brightest: CGFloat = 0
        var inked = 0
        for x in 0 ..< rep.pixelsWide {
            for y in 0 ..< rep.pixelsHigh {
                guard let pixel = rep.colorAt(x: x, y: y), pixel.alphaComponent > 0.5,
                      let color = pixel.usingColorSpace(.sRGB) else { continue }
                inked += 1
                brightest = max(brightest, color.brightnessComponent)
            }
        }
        #expect(inked > 20)
        #expect(brightest > 0.8)
    }
}

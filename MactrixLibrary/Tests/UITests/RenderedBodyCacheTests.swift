import AppKit
@testable import MessageFormatting
import Testing

/// MATRIX-174: `renderHTML` keeps its renders by font size and body.
@MainActor
struct RenderedBodyCacheTests {
    @Test func theSameBodyAndSizeGiveTheSameRender() {
        let body = "<p>cache <strong>one</strong> render</p>"
        #expect(renderHTML(body, baseFontSize: 13) === renderHTML(body, baseFontSize: 13))
    }

    @Test func theFontSizeIsPartOfTheKey() {
        let body = "<p>cache two sizes</p>"
        let small = renderHTML(body, baseFontSize: 13)
        let large = renderHTML(body, baseFontSize: 26)
        let smallFont = small.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let largeFont = large.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(smallFont?.pointSize == 13)
        #expect(largeFont?.pointSize == 26)
    }

    /// The resolver edits a copy, so a second parse of an emoticon body still
    /// finds the markers in the cached render.
    @Test func anEmoticonBodyParsesTheSameTwice() {
        let loader = EmoticonStubLoader(colors: ["mxc://example.org/parrot": .stubGreen])
        let body = "<p>cache \(BodyEmoticonTests.parrot) markers</p>"
        let first = parseFormattedBody(body, baseFontSize: 13, imageLoader: loader)
        let second = parseFormattedBody(body, baseFontSize: 13, imageLoader: loader)
        #expect(first.string == second.string)
        #expect(second.containsAttachments)
        #expect(!second.string.contains(ImageTagRewriter.openMarker))
    }
}

import AppKit
@testable import MessageFormatting
import Models
import SwiftUI
import Testing
import Tokens
import UI

/// Serves a solid-color square for each known URL, from the cache, and
/// records every load it is asked for.
@MainActor
final class EmoticonStubLoader: ImageLoader {
    var colors: [String: NSColor]
    private(set) var loadRequests: [String] = []
    private(set) var cacheRequests: [String] = []

    init(colors: [String: NSColor] = [:]) {
        self.colors = colors
    }

    func cachedImage(matrixUrl: String) -> Image? {
        cacheRequests.append(matrixUrl)
        guard let color = colors[matrixUrl] else { return nil }
        let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
        return Image(nsImage: image)
    }

    /// What a load puts in the cache, for a URL the cache does not hold yet.
    var arrivingColors: [String: NSColor] = [:]

    func loadImage(matrixUrl: String, size _: CGSize?) async throws -> Image? {
        loadRequests.append(matrixUrl)
        if let color = arrivingColors[matrixUrl] {
            colors[matrixUrl] = color
        }
        return cachedImage(matrixUrl: matrixUrl)
    }
}

/// MATRIX-153: `<img>` in a message's HTML body.
@MainActor
struct BodyEmoticonTests {
    /// The exact tag the Slack bridge writes (research note A1).
    static let parrot = #"<img data-mx-emoticon src="mxc://example.org/parrot" alt=":partyparrot:" title=":partyparrot:" height="32"/>"#

    private func attachments(in string: NSAttributedString) -> [NSTextAttachment] {
        var found: [NSTextAttachment] = []
        string.enumerateAttribute(.attachment, in: NSRange(location: 0, length: string.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment {
                found.append(attachment)
            }
        }
        return found
    }

    private func height(of string: NSAttributedString, width: CGFloat = 300) -> CGFloat {
        let field = NSTextField(labelWithAttributedString: string)
        field.lineBreakMode = .byWordWrapping
        field.usesSingleLineMode = false
        field.preferredMaxLayoutWidth = width
        let bounds = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)
        return ceil(field.cell?.cellSize(forBounds: bounds).height ?? 0)
    }

    // MARK: Rewriter

    @Test func emoticonBecomesMarkedAltText() {
        let output = ImageTagRewriter.rewrite("ship it \(Self.parrot) now")
        #expect(output.html == "ship it \u{FFF9}:partyparrot:\u{FFFB} now")
        #expect(output.emoticonSources == ["mxc://example.org/parrot"])
    }

    @Test func plainImageBecomesAltText() {
        let output = ImageTagRewriter.rewrite(#"a <img src="https://tracker.example/pixel.png" alt="chart"> b"#)
        #expect(output.html == "a chart b")
        #expect(output.emoticonSources.isEmpty)
    }

    @Test func imageWithoutAltBecomesNothing() {
        let output = ImageTagRewriter.rewrite(#"a<img src="https://tracker.example/pixel.png">b"#)
        #expect(output.html == "ab")
        #expect(output.emoticonSources.isEmpty)
    }

    /// The emoticon flag does not make a remote source loadable.
    @Test(arguments: [
        #"<img data-mx-emoticon src="https://tracker.example/e.png" alt=":e:">"#,
        #"<img data-mx-emoticon src="http://tracker.example/e.png" alt=":e:">"#,
        #"<img data-mx-emoticon src="file:///etc/passwd" alt=":e:">"#,
        #"<img data-mx-emoticon src="mxc://" alt=":e:">"#,
        #"<img data-mx-emoticon alt=":e:">"#,
        #"<img src="mxc://example.org/media" alt=":e:">"#,
        #"<IMG SRC='https://tracker.example/e.png' ALT=':e:'>"#,
        #"<img src=https://tracker.example/e.png alt=:e:>"#,
        #"<img title="a > b" src="https://tracker.example/e.png" alt=":e:"></img>"#,
    ])
    func otherImagesAreAltTextOnly(tag: String) {
        let output = ImageTagRewriter.rewrite(tag)
        #expect(output.html == ":e:")
        #expect(output.emoticonSources.isEmpty)
    }

    @Test func altTextCannotOpenATag() {
        let output = ImageTagRewriter.rewrite(#"<img src="https://a.example/x" alt="<img src='https://b.example/y'>">"#)
        #expect(output.html == "&lt;img src='https://b.example/y'&gt;")
        #expect(ImageTagRewriter.rewrite(output.html) == output)
    }

    @Test func forgedMarkersAreRemoved() {
        let output = ImageTagRewriter.rewrite("a \u{FFF9}:fake:\u{FFFB} b")
        #expect(output.html == "a :fake: b")
        #expect(output.emoticonSources.isEmpty)
    }

    @Test func sourcesListHasNoDuplicates() {
        let other = #"<img data-mx-emoticon src="mxc://example.org/other" alt=":other:">"#
        #expect(
            emoticonSources(inFormattedBody: Self.parrot + other + Self.parrot)
                == ["mxc://example.org/parrot", "mxc://example.org/other"]
        )
    }

    // MARK: Privacy

    /// No `<img>` form gives a remote attachment. The only attachment type
    /// the parser makes is `EmoticonAttachment`, which holds a finished
    /// image and no URL to fetch.
    @Test(arguments: [
        #"<p>a <img src="https://tracker.example/pixel.png" alt="chart"> b</p>"#,
        #"<p>a <img src="https://tracker.example/pixel.png"> b</p>"#,
        #"<p>a <img data-mx-emoticon src="https://tracker.example/e.png" alt=":e:"> b</p>"#,
        #"<p>a <img src="https://tracker.example/pixel.png" alt="unclosed quote> b</p>"#,
        #"<p>a <img src="https://tracker.example/pixel.png" b</p>"#,
        #"<a href="https://example.org"><img src="https://tracker.example/pixel.png" width="1" height="1"/></a>"#,
    ])
    func remoteImageMakesNoAttachment(html: String) {
        let loader = EmoticonStubLoader()
        let rendered = parseFormattedBody(html, imageLoader: loader)
        #expect(attachments(in: rendered).isEmpty)
        #expect(loader.cacheRequests.isEmpty)
        #expect(loader.loadRequests.isEmpty)
    }

    /// The renderer by itself, with no rewrite before it: the default image
    /// handler (the `URLSession` one) is not registered, so a raw `<img>`
    /// makes no attachment at all.
    @Test(arguments: [
        #"<p>a <img src="https://tracker.example/pixel.png" alt="chart"> b</p>"#,
        #"<p>a <img src="https://tracker.example/pixel.png" width="20" height="20"/> b</p>"#,
        #"<p>a <IMG SRC="https://tracker.example/pixel.png"> b</p>"#,
        #"<p>a <img data-mx-emoticon src="mxc://example.org/parrot" alt=":p:"/> b</p>"#,
    ])
    func rendererAloneMakesNoImageAttachment(html: String) {
        let rendered = renderHTML(html, baseFontSize: 13)
        #expect(attachments(in: rendered).isEmpty)
    }

    @Test func everyAttachmentIsAnEmoticonAttachment() {
        let html = "<p>\(Self.parrot) and <img src=\"https://tracker.example/pixel.png\" alt=\"x\"> and \(Self.parrot)</p>"
        let found = attachments(in: parseFormattedBody(html, imageLoader: EmoticonStubLoader()))
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0 is EmoticonAttachment })
    }

    // MARK: Emoticon rendering

    @Test func plainImageRendersAsAltText() {
        let rendered = parseFormattedBody(#"<p>a <img src="https://tracker.example/pixel.png" alt="chart &amp; table"> b</p>"#)
        #expect(rendered.string.trimmingCharacters(in: .whitespacesAndNewlines) == "a chart & table b")
    }

    @Test func emoticonWithoutCachedImageDrawsAltText() throws {
        let loader = EmoticonStubLoader()
        let rendered = parseFormattedBody("<p>ship it \(Self.parrot)</p>", imageLoader: loader)
        let attachment = try #require(attachments(in: rendered).first as? EmoticonAttachment)
        #expect(attachment.source == "mxc://example.org/parrot")
        #expect(attachment.alt == ":partyparrot:")
        #expect(!attachment.isLoaded)
        #expect(!rendered.string.contains("\u{FFF9}"))
        #expect(!rendered.string.contains("\u{FFFB}"))
        // Parsing reads the cache. It never starts a load.
        #expect(loader.cacheRequests == ["mxc://example.org/parrot"])
        #expect(loader.loadRequests.isEmpty)
    }

    @Test func emoticonWithCachedImageDrawsTheImage() throws {
        let loader = EmoticonStubLoader(colors: ["mxc://example.org/parrot": .systemGreen])
        let rendered = parseFormattedBody("<p>ship it \(Self.parrot)</p>", imageLoader: loader)
        let attachment = try #require(attachments(in: rendered).first as? EmoticonAttachment)
        #expect(attachment.isLoaded)
        #expect(attachment.image != nil)
    }

    @Test func emoticonWithNoLoaderDrawsAltText() throws {
        let rendered = parseFormattedBody("<p>ship it \(Self.parrot)</p>")
        let attachment = try #require(attachments(in: rendered).first as? EmoticonAttachment)
        #expect(!attachment.isLoaded)
    }

    // MARK: Row height

    /// The square is known from the font alone: the same bounds with and
    /// without the image, and no taller than the text line.
    @Test(arguments: [CGFloat(11), 13, 15, 20])
    func boundsDoNotDependOnTheImage(fontSize: CGFloat) throws {
        let html = "<p>ship it \(Self.parrot) now</p>"
        let pending = parseFormattedBody(html, baseFontSize: fontSize, imageLoader: EmoticonStubLoader())
        let loaded = parseFormattedBody(
            html,
            baseFontSize: fontSize,
            imageLoader: EmoticonStubLoader(colors: ["mxc://example.org/parrot": .systemGreen])
        )
        let pendingBounds = try #require(attachments(in: pending).first).bounds
        let loadedBounds = try #require(attachments(in: loaded).first).bounds
        #expect(pendingBounds == loadedBounds)
        #expect(pendingBounds.width == pendingBounds.height)

        let font = NSFont.systemFont(ofSize: fontSize)
        #expect(pendingBounds.height <= font.ascender - font.descender)
        #expect(pendingBounds.minY == font.descender)
    }

    /// A body lays out at one height with the alt text, with the image, and
    /// with plain text in place of the emoticon, on one line and wrapped.
    @Test(arguments: [CGFloat(11), 13, 15, 20])
    func heightIsTheSameBeforeAndAfterTheImageLoads(fontSize: CGFloat) {
        let filler = "The quick brown fox jumps over the lazy dog. "
        for prefix in ["", filler, filler + filler + filler] {
            let html = "<p>\(prefix)ship it \(Self.parrot) now</p>"
            let pending = parseFormattedBody(html, baseFontSize: fontSize, imageLoader: EmoticonStubLoader())
            let loaded = parseFormattedBody(
                html,
                baseFontSize: fontSize,
                imageLoader: EmoticonStubLoader(colors: ["mxc://example.org/parrot": .systemGreen])
            )
            let textOnly = parseFormattedBody("<p>\(prefix)ship it xx now</p>", baseFontSize: fontSize)
            #expect(height(of: pending) == height(of: loaded))
            // Text of another width can wrap at another word, so the
            // text-only comparison holds for the one-line body only.
            if prefix.isEmpty {
                #expect(height(of: pending) == height(of: textOnly))
            }
        }
    }

    /// The view loads a missing image through the loader, then draws the
    /// body again in place, at the same size.
    @Test func lateImageRedrawsInPlaceAtTheSameSize() async throws {
        let html = "<p>ship it \(Self.parrot) now</p>"
        func host(_ loader: EmoticonStubLoader) -> (NSHostingController<AnyView>, NSWindow) {
            let controller = NSHostingController(
                rootView: AnyView(
                    FormattedBodyText(html: html, baseFontSize: 13, imageLoader: loader)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 300)
                )
            )
            // The window is never put on screen. It lets the view's task run.
            let window = NSWindow(contentViewController: controller)
            controller.view.layoutSubtreeIfNeeded()
            return (controller, window)
        }

        // This loader never gets the image: the alt text stays.
        let (pending, pendingWindow) = host(EmoticonStubLoader())
        defer { pendingWindow.close() }

        // This loader gets the image when the view asks for the load.
        let loader = EmoticonStubLoader()
        loader.arrivingColors = ["mxc://example.org/parrot": .systemGreen]
        let (arriving, arrivingWindow) = host(loader)
        defer { arrivingWindow.close() }
        let field = try #require(Self.textField(in: arriving.view))

        var loadedAttachment: EmoticonAttachment?
        for _ in 0 ..< 200 where loadedAttachment == nil {
            try await Task.sleep(for: .milliseconds(10))
            loadedAttachment = attachments(in: field.attributedStringValue)
                .compactMap { $0 as? EmoticonAttachment }
                .first { $0.isLoaded }
        }
        #expect(loadedAttachment != nil)
        #expect(loader.loadRequests == ["mxc://example.org/parrot"])

        let pendingField = try #require(Self.textField(in: pending.view))
        let pendingAttachments = attachments(in: pendingField.attributedStringValue).compactMap { $0 as? EmoticonAttachment }
        #expect(pendingAttachments.count == 1)
        #expect(pendingAttachments.allSatisfy { !$0.isLoaded })

        arriving.view.layoutSubtreeIfNeeded()
        pending.view.layoutSubtreeIfNeeded()
        #expect(arriving.view.fittingSize == pending.view.fittingSize)
        #expect(arriving.view.fittingSize.height > 0)
    }

    private static func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        for subview in view.subviews {
            if let field = textField(in: subview) { return field }
        }
        return nil
    }

    /// A body of only custom emoticons is not a jumbo-emoji message
    /// (MATRIX-137 covers Unicode emoji only).
    @Test func emoticonOnlyBodyIsNotJumbo() {
        #expect(Models.JumboEmoji.jumboText(body: ":partyparrot:", formattedBody: Self.parrot) == nil)
    }
}

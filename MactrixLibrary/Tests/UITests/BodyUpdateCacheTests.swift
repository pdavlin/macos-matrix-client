import AppKit
@testable import MessageFormatting
import SwiftUI
import Testing
import UI

/// MATRIX-182: an update of a row with an equal body does not parse the body
/// again, and the parse does not draw a cached emoticon image again.
@MainActor
struct BodyUpdateCacheTests {
    /// A source that no other test uses, so no other test puts a render of it
    /// in the process-wide render cache.
    private static let source = "mxc://example.org/render-cache-182"
    private static let html = #"<p>ship it <img data-mx-emoticon src="\#(source)" alt=":ship:" height="32"/> now</p>"#

    private static func handler(_ id: String) -> BodyEmoticonHandler {
        BodyEmoticonHandler(id: id) { _ in }
    }

    private static func emoticonAttachments(in string: NSAttributedString) -> [EmoticonAttachment] {
        var found: [EmoticonAttachment] = []
        string.enumerateAttribute(.attachment, in: NSRange(location: 0, length: string.length)) { value, _, _ in
            if let attachment = value as? EmoticonAttachment {
                found.append(attachment)
            }
        }
        return found
    }

    // MARK: Equal inputs

    private static func content(
        html: String = BodyUpdateCacheTests.html,
        baseFontSize: CGFloat = 13,
        imageLoader: (any ImageLoader)?,
        onEmoticons: BodyEmoticonHandler?
    ) -> FormattedBodyContent {
        FormattedBodyContent(
            html: html,
            baseFontSize: baseFontSize,
            isJumbo: false,
            imageLoader: imageLoader,
            onEmoticons: onEmoticons,
            marksMusicLinks: false,
            musicLinkTitles: nil
        )
    }

    /// Two handlers with one id are equal, though their closures differ.
    @Test func handlersWithOneIdAreEqual() {
        #expect(Self.handler("!room:example.org") == Self.handler("!room:example.org"))
        #expect(Self.handler("!room:example.org") != Self.handler("!other:example.org"))
    }

    @Test func bodiesWithEqualInputsAreEqual() {
        let loader = EmoticonStubLoader()
        let first = Self.content(imageLoader: loader, onEmoticons: Self.handler("!room:example.org"))
        let second = Self.content(imageLoader: loader, onEmoticons: Self.handler("!room:example.org"))
        #expect(first == second)
    }

    @Test func eachInputTakesPartInTheComparison() {
        let loader = EmoticonStubLoader()
        let base = Self.content(imageLoader: loader, onEmoticons: Self.handler("!room:example.org"))
        #expect(base != Self.content(html: "<p>other</p>", imageLoader: loader, onEmoticons: Self.handler("!room:example.org")))
        #expect(base != Self.content(baseFontSize: 26, imageLoader: loader, onEmoticons: Self.handler("!room:example.org")))
        #expect(base != Self.content(imageLoader: EmoticonStubLoader(), onEmoticons: Self.handler("!room:example.org")))
        #expect(base != Self.content(imageLoader: nil, onEmoticons: Self.handler("!room:example.org")))
        #expect(base != Self.content(imageLoader: loader, onEmoticons: Self.handler("!other:example.org")))
        #expect(base != Self.content(imageLoader: loader, onEmoticons: nil))
    }

    /// A loader that is not an object has no identity to compare, so the
    /// body is evaluated again as before MATRIX-182.
    @Test func aValueLoaderIsNeverEqual() {
        let loader = StubImageLoader(colors: [:])
        #expect(Self.content(imageLoader: loader, onEmoticons: nil) != Self.content(imageLoader: loader, onEmoticons: nil))
    }

    // MARK: Row updates

    @MainActor
    private final class Reports {
        var count = 0
    }

    private struct Row: View {
        let loader: EmoticonStubLoader
        let handler: BodyEmoticonHandler

        var body: some View {
            FormattedBodyText(html: BodyUpdateCacheTests.html, baseFontSize: 13, imageLoader: loader, onEmoticons: handler)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 300)
        }
    }

    /// Hosts the row, waits for its task to report the emoticon, then builds
    /// the row ten times more with the handler of each step. Returns the
    /// number of parses the ten updates made: each parse asks the loader's
    /// cache for the one emoticon.
    private func parsesForTenUpdates(handler: (Int, Reports) -> BodyEmoticonHandler) async throws -> Int {
        let loader = EmoticonStubLoader(colors: [Self.source: .stubGreen])
        let reports = Reports()
        let controller = NSHostingController(rootView: Row(loader: loader, handler: handler(0, reports)))
        // The window is never put on screen. It lets the view's task run.
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        controller.view.layoutSubtreeIfNeeded()

        // The task reports the emoticon, then reads the cache for each image
        // with no wait between the two.
        for _ in 0 ..< 200 where reports.count == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(reports.count == 1)

        let before = loader.cacheRequests.count
        for step in 1 ... 10 {
            controller.rootView = Row(loader: loader, handler: handler(step, reports))
            controller.view.layoutSubtreeIfNeeded()
        }
        return loader.cacheRequests.count - before
    }

    /// The row makes a new closure on each update. Before MATRIX-182 each
    /// update parsed the body again.
    @Test func anUpdateWithAnEqualHandlerDoesNotParse() async throws {
        let parses = try await parsesForTenUpdates { _, reports in
            BodyEmoticonHandler(id: "!room:example.org") { _ in reports.count += 1 }
        }
        #expect(parses == 0)
    }

    /// The control: the same updates with a new id each time reach the body.
    @Test func anUpdateWithAnotherHandlerParses() async throws {
        let parses = try await parsesForTenUpdates { step, reports in
            BodyEmoticonHandler(id: "!room\(step):example.org") { _ in reports.count += 1 }
        }
        #expect(parses >= 10)
    }

    // MARK: Emoticon render cache

    @Test func aCachedEmoticonIsDrawnOnceForEachSide() throws {
        let loader = EmoticonStubLoader(colors: [Self.source: .stubGreen])
        func drawnImage() throws -> NSImage? {
            let attachment = try #require(
                Self.emoticonAttachments(in: parseFormattedBody(Self.html, baseFontSize: 13, imageLoader: loader)).first
            )
            #expect(attachment.isLoaded)
            #expect(attachment.image != nil)
            return attachment.image
        }

        // The loader makes a new image for each call, so with no cache no two
        // parses share a drawn image. `NSCache` can remove an image at any
        // time under memory pressure, so one pair of parses can miss.
        var shared = false
        for _ in 0 ..< 5 where !shared {
            shared = try drawnImage() === drawnImage()
        }
        #expect(shared)
        // Each parse still asks the loader.
        #expect(loader.cacheRequests.count >= 2)
        #expect(Set(loader.cacheRequests) == [Self.source])
    }

    @Test func theSideIsPartOfTheKey() throws {
        let loader = EmoticonStubLoader(colors: [Self.source: .stubGreen])
        let small = try #require(Self.emoticonAttachments(in: parseFormattedBody(Self.html, baseFontSize: 13, imageLoader: loader)).first)
        let large = try #require(Self.emoticonAttachments(in: parseFormattedBody(Self.html, baseFontSize: 26, imageLoader: loader)).first)
        let smallImage = try #require(small.image)
        let largeImage = try #require(large.image)
        #expect(smallImage !== largeImage)
        #expect(smallImage.size.width == small.bounds.width)
        #expect(largeImage.size.width == large.bounds.width)
        #expect(largeImage.size.width > smallImage.size.width)
    }

    /// The cache does not replace the loader: a source whose image the loader
    /// does not hold draws its alt text, though the cache holds a render.
    @Test func aSourceTheLoaderDoesNotHoldDrawsItsAltText() throws {
        _ = parseFormattedBody(Self.html, baseFontSize: 13, imageLoader: EmoticonStubLoader(colors: [Self.source: .stubGreen]))
        let empty = EmoticonStubLoader()
        let pending = try #require(Self.emoticonAttachments(in: parseFormattedBody(Self.html, baseFontSize: 13, imageLoader: empty)).first)
        #expect(!pending.isLoaded)
        let unloaded = try #require(Self.emoticonAttachments(in: parseFormattedBody(Self.html, baseFontSize: 13, imageLoader: nil)).first)
        #expect(!unloaded.isLoaded)
    }

    /// The bound: 8 MB of pixel bytes, at the Mac's render scale of 2.
    @Test func theCacheHasACostLimit() {
        #expect(EmoticonResolver.renderedImages.totalCostLimit == 8 * 1024 * 1024)
        #expect(EmoticonResolver.renderCost(side: 15) == 30 * 30 * 4)
    }
}

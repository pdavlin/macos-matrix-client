import AppKit
@testable import MessageFormatting
import SwiftUI
import Testing
import Tokens

/// MATRIX-187: the gradient bar under a music link.
///
/// The bar draws in a background view behind the body's `NSTextField`.
/// These tests prove that it does not change the row height (MATRIX-153),
/// and that the bar rects, which come from a TextKit 1 stack, fall where
/// the text field draws the link text.
@MainActor
struct MusicLinkBarTests {
    nonisolated static let posted = "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=0123456789abcdef"
    nonisolated static let oneLine = #"<p>listen to <a href="\#(posted)">this song</a> now</p>"#
    nonisolated static let wrapped = #"<p>listen to <a href="\#(posted)">this song with a long name that wraps</a> now</p>"#
    nonisolated static let width: CGFloat = 200

    /// The case of each test: the body and its number of bar rects.
    enum Body: CaseIterable {
        case oneLine, wrapped

        var html: String {
            switch self {
            case .oneLine: MusicLinkBarTests.oneLine
            case .wrapped: MusicLinkBarTests.wrapped
            }
        }

        var lines: Int {
            switch self {
            case .oneLine: 1
            case .wrapped: 2
            }
        }
    }

    /// The body as `AttributedTextView` holds it.
    private func marked(_ body: Body) -> NSAttributedString {
        AttributedTextView(attributedString: parseFormattedBody(body.html, baseFontSize: 13, marksMusicLinks: true))
            .attributedString
    }

    private func withoutBar(_ string: NSAttributedString) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: string)
        copy.removeAttribute(.musicLinkMarker, range: NSRange(location: 0, length: copy.length))
        return copy
    }

    /// A view hosted at the test width, laid out as the timeline lays out a body.
    private func hosted(_ view: some View, appearance: NSAppearance.Name = .aqua) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(view.fixedSize(horizontal: false, vertical: true).frame(width: Self.width, alignment: .leading))
        )
        controller.view.appearance = NSAppearance(named: appearance)
        controller.view.frame.size = controller.view.fittingSize
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    private func body(_ body: Body, appearance: NSAppearance.Name = .aqua) -> NSHostingController<AnyView> {
        hosted(FormattedBodyText(html: body.html, baseFontSize: 13, imageLoader: nil, marksMusicLinks: true), appearance: appearance)
    }

    private static func first<T: NSView>(_: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = first(T.self, in: subview) { return match }
        }
        return nil
    }

    /// The bar rects of the hosted body, in the host view, with y from the top.
    private func barRects(in host: NSView) throws -> [CGRect] {
        let field = try #require(Self.first(NSTextField.self, in: host))
        return MusicLinkBar.rects(for: field.attributedStringValue, in: field.bounds).map { rect in
            let converted = host.convert(rect, from: field)
            guard !host.isFlipped else { return converted }
            return CGRect(x: converted.minX, y: host.bounds.height - converted.maxY, width: converted.width, height: converted.height)
        }
    }

    // MARK: Height

    /// The measured height of a marked body is the height of the same body
    /// without the bar, for one line and for a link that wraps.
    @Test(arguments: Body.allCases)
    func theBarDoesNotChangeTheHeight(body: Body) throws {
        let withBar = self.body(body)
        let barView = try #require(Self.first(MusicLinkBarView.self, in: withBar.view))
        #expect(try barRects(in: withBar.view).count == body.lines)

        let string = marked(body)
        let noBar = hosted(AttributedTextView(attributedString: withoutBar(string)))
        #expect(Self.first(MusicLinkBarView.self, in: noBar.view) == nil)
        #expect(withBar.view.fittingSize.height == noBar.view.fittingSize.height)
        #expect(withBar.view.fittingSize.height > 0)

        // The bar view has the text field's layout frame: the field's frame
        // less its alignment insets.
        let field = try #require(Self.first(NSTextField.self, in: withBar.view))
        let fieldFrame = withBar.view.convert(field.bounds, from: field)
        let insets = field.alignmentRectInsets
        let layoutFrame = CGRect(
            x: fieldFrame.minX + insets.left,
            y: fieldFrame.minY + (withBar.view.isFlipped ? insets.top : insets.bottom),
            width: fieldFrame.width - insets.left - insets.right,
            height: fieldFrame.height - insets.top - insets.bottom
        )
        #expect(withBar.view.convert(barView.bounds, from: barView) == layoutFrame)
    }

    /// Each bar is 3 pt tall and stays inside its line: below the baseline,
    /// and above the bottom of the line.
    @Test(arguments: Body.allCases)
    func eachBarIsInsideItsLine(body: Body) {
        let font = NSFont.systemFont(ofSize: 13)
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        let baseline = NSLayoutManager().defaultBaselineOffset(for: font)
        let rects = MusicLinkBar.rects(for: marked(body), in: CGRect(x: 0, y: 0, width: Self.width, height: 1000))
        #expect(rects.count == body.lines)
        for (line, rect) in rects.enumerated() {
            let lineTop = CGFloat(line) * lineHeight
            #expect(rect.height == MusicLinkToken.barThickness)
            #expect(rect.minY >= lineTop + baseline - 0.5)
            #expect(rect.maxY <= lineTop + lineHeight)
            #expect(rect.width > 10)
        }
    }

    @Test func aBodyWithNoMusicLinkHasNoBar() {
        let controller = hosted(FormattedBodyText(html: Self.oneLine, baseFontSize: 13, imageLoader: nil))
        #expect(Self.first(MusicLinkBarView.self, in: controller.view) == nil)
        #expect(!MusicLinkBar.hasMarker(parseFormattedBody(Self.oneLine, baseFontSize: 13)))
    }

    @Test func theBarTakesNoClicks() throws {
        let controller = body(.oneLine)
        let barView = try #require(Self.first(MusicLinkBarView.self, in: controller.view))
        #expect(barView.hitTest(NSPoint(x: 5, y: 5)) == nil)
    }

    // MARK: Click areas

    /// A rect in the hosted body's text field, in the host view, with y from the top.
    private func hostRect(_ rect: CGRect, from field: NSTextField, in host: NSView) -> CGRect {
        let converted = host.convert(rect, from: field)
        guard !host.isFlipped else { return converted }
        return CGRect(x: converted.minX, y: host.bounds.height - converted.maxY, width: converted.width, height: converted.height)
    }

    /// The view that takes a click at `point` of the host view, with y from the top.
    private func hit(_ point: CGPoint, in host: NSView) -> NSView? {
        let local = host.isFlipped ? point : NSPoint(x: point.x, y: host.bounds.height - point.y)
        return host.hitTest(host.superview.map { host.convert(local, to: $0) } ?? local)
    }

    private func isInside(_ view: NSView?, _ field: NSTextField) -> Bool {
        guard let view else { return false }
        return view === field || view.isDescendant(of: field)
    }

    /// The glyph and the text of the link open song.link: each line of the
    /// link has a click area over the glyph and the text, with the song.link
    /// URL. A click there does not reach the text field. A click on the
    /// other text does, so the body stays selectable.
    @Test(arguments: Body.allCases)
    func theClickAreasOpenSongLink(body: Body) throws {
        let controller = self.body(body)
        let host = controller.view
        // SwiftUI hit tests a hosting view only in a window.
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let field = try #require(Self.first(NSTextField.self, in: host))
        let string = field.attributedStringValue
        let targets = MusicLinkBar.targets(for: string, in: field.bounds)
        let bars = MusicLinkBar.rects(for: string, in: field.bounds)
        #expect(targets.count == body.lines)
        #expect(bars.count == body.lines)
        let songLink = "https://song.link/https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"
        #expect(targets.allSatisfy { $0.url.absoluteString == songLink })
        #expect(targets.map(\.text).joined(separator: " ").hasPrefix("this song"))

        for (target, bar) in zip(targets, bars) {
            // The area covers the bar's text, and the glyph on the first line.
            #expect(target.rect.minX <= bar.minX)
            #expect(target.rect.maxX >= bar.maxX - 0.5)
            #expect(target.rect.minY < bar.minY)
            #expect(target.rect.maxY >= bar.maxY)
        }
        let firstTarget = try #require(targets.first)
        let firstBar = try #require(bars.first)
        #expect(firstTarget.rect.minX < firstBar.minX - 5)
        for target in targets {
            let rect = hostRect(target.rect, from: field, in: host)
            let hit = self.hit(CGPoint(x: rect.midX, y: rect.midY), in: host)
            #expect(hit != nil)
            #expect(!isInside(hit, field))
        }
        // "listen" at the start of the body goes to the text field.
        let start = hostRect(CGRect(x: 6, y: 4, width: 1, height: 1), from: field, in: host)
        #expect(isInside(hit(CGPoint(x: start.midX, y: start.midY), in: host), field))
    }

    // MARK: Pixels

    private struct Bitmap {
        let rep: NSBitmapImageRep
        let scale: CGFloat

        func color(x: CGFloat, y: CGFloat) -> NSColor? {
            rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB)
        }

        /// True if a pixel in the point rect has ink.
        func hasInk(in rect: CGRect) -> Bool {
            let minX = max(0, Int(rect.minX * scale))
            let maxX = min(rep.pixelsWide, Int(rect.maxX * scale))
            let minY = max(0, Int(rect.minY * scale))
            let maxY = min(rep.pixelsHigh, Int(rect.maxY * scale))
            guard minX < maxX, minY < maxY else { return false }
            for x in minX ..< maxX {
                for y in minY ..< maxY where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 {
                    return true
                }
            }
            return false
        }
    }

    private func render(_ view: NSView) throws -> Bitmap {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return Bitmap(rep: rep, scale: CGFloat(rep.pixelsWide) / view.bounds.width)
    }

    private func isClose(_ color: NSColor?, to expected: NSColor, tolerance: CGFloat = 0.08) -> Bool {
        guard let color, let expected = expected.usingColorSpace(.sRGB) else { return false }
        return abs(color.redComponent - expected.redComponent) <= tolerance
            && abs(color.greenComponent - expected.greenComponent) <= tolerance
            && abs(color.blueComponent - expected.blueComponent) <= tolerance
            && color.alphaComponent > 0.95
    }

    /// The drawn bar has the four stops, left to right, on each line. It
    /// starts at the first glyph of the link text and ends at the last.
    @Test(arguments: Body.allCases, [NSAppearance.Name.aqua, .darkAqua])
    func theDrawnBarSpansTheLinkOnEachLine(body: Body, appearance: NSAppearance.Name) throws {
        let controller = self.body(body, appearance: appearance)
        let bitmap = try render(controller.view)
        let stops = MusicLinkToken.barStops
        let rects = try barRects(in: controller.view)
        #expect(rects.count == body.lines)
        for rect in rects {
            let midY = rect.midY
            #expect(isClose(bitmap.color(x: rect.minX + 1, y: midY), to: stops[0].color))
            #expect(isClose(bitmap.color(x: rect.minX + rect.width * stops[1].location, y: midY), to: stops[1].color))
            #expect(isClose(bitmap.color(x: rect.minX + rect.width * stops[2].location, y: midY), to: stops[2].color))
            #expect(isClose(bitmap.color(x: rect.maxX - 1, y: midY), to: stops[3].color))
            // No bar past either end.
            #expect(!bitmap.hasInk(in: CGRect(x: rect.maxX + 1, y: rect.minY + 1, width: 2, height: 1)))
            #expect(!bitmap.hasInk(in: CGRect(x: rect.minX - 2.5, y: rect.minY + 1, width: 1.5, height: 1)))

            // The text field draws the link text over the bar's ends: ink in
            // the x-height band at each end, none in the space after it.
            func band(from minX: CGFloat, to maxX: CGFloat) -> CGRect {
                CGRect(x: minX, y: rect.minY - 6, width: maxX - minX, height: 5)
            }
            #expect(bitmap.hasInk(in: band(from: rect.minX, to: rect.minX + 3)))
            #expect(bitmap.hasInk(in: band(from: rect.maxX - 3, to: rect.maxX)))
            #expect(!bitmap.hasInk(in: band(from: rect.maxX + 0.5, to: rect.maxX + 2.5)))
        }
    }

    /// The link text draws in the body text color, not in the link blue:
    /// each solid pixel of the link text is a gray, light or dark as the
    /// text of the body around it.
    @Test(arguments: Body.allCases, [NSAppearance.Name.aqua, .darkAqua])
    func theLinkTextHasTheBodyColor(body: Body, appearance: NSAppearance.Name) throws {
        let controller = self.body(body, appearance: appearance)
        let bitmap = try render(controller.view)
        let rects = try barRects(in: controller.view)
        #expect(rects.count == body.lines)
        var solid = 0
        for rect in rects {
            // The band above the bar, where the link text's glyphs are.
            let minX = Int(rect.minX * bitmap.scale)
            let maxX = Int(rect.maxX * bitmap.scale)
            let minY = Int((rect.minY - 9) * bitmap.scale)
            let maxY = Int((rect.minY - 1) * bitmap.scale)
            for x in minX ..< maxX {
                for y in minY ..< maxY {
                    guard let color = bitmap.rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                          color.alphaComponent > 0.6
                    else { continue }
                    solid += 1
                    let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                    let spread = (channels.max() ?? 0) - (channels.min() ?? 0)
                    #expect(spread < 0.1, "a colored pixel at \(x), \(y): \(color)")
                    if appearance == .aqua {
                        #expect(color.redComponent < 0.4)
                    } else {
                        #expect(color.redComponent > 0.6)
                    }
                }
            }
        }
        #expect(solid > 20)
    }

    /// The glyph's light violet has a contrast of at least 3:1 on white.
    @Test func theGlyphColorHasContrastOnWhite() {
        func luminance(_ rgb: UInt32) -> Double {
            let channels = [(rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF].map { Double($0) / 255 }
            let linear = channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        let contrast = 1.05 / (luminance(MusicLinkToken.glyphLightRGB) + 0.05)
        #expect(contrast >= 3)
        #expect(MusicLinkToken.glyphDarkRGB == 0xA78BFA)
    }
}

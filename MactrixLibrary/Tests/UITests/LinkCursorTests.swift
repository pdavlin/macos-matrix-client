import AppKit
@testable import MessageFormatting
import SwiftUI
import Testing

/// MATRIX-190: the pointing hand over the links of a message body.
///
/// The body's `LinkCursorTextField` sets the cursor from its link rects.
/// These tests prove that the link rects fall where the field draws the link
/// text: one rect for a link on one line, two for a link that wraps.
@MainActor
struct LinkCursorTests {
    nonisolated static let posted = "https://example.org/a/page"
    nonisolated static let oneLine = #"<p>listen to <a href="\#(posted)">this song</a> now</p>"#
    nonisolated static let wrapped = #"<p>listen to <a href="\#(posted)">this song with a long name that wraps</a> now</p>"#
    nonisolated static let mention = #"<p>hi <a href="https://matrix.to/#/@alice:example.org">Alice</a> there</p>"#
    nonisolated static let spotify = "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"
    nonisolated static let width: CGFloat = 200

    enum Body: CaseIterable {
        case oneLine, wrapped

        var html: String {
            switch self {
            case .oneLine: LinkCursorTests.oneLine
            case .wrapped: LinkCursorTests.wrapped
            }
        }

        var lines: Int {
            switch self {
            case .oneLine: 1
            case .wrapped: 2
            }
        }
    }

    /// The body hosted at the test width, laid out as the timeline lays out a body.
    private func hosted(_ html: String, marksMusicLinks: Bool = false) -> NSHostingController<AnyView> {
        let view = FormattedBodyText(html: html, baseFontSize: 13, imageLoader: nil, marksMusicLinks: marksMusicLinks)
        let controller = NSHostingController(
            rootView: AnyView(view.fixedSize(horizontal: false, vertical: true).frame(width: Self.width, alignment: .leading))
        )
        controller.view.appearance = NSAppearance(named: .aqua)
        controller.view.frame.size = controller.view.fittingSize
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    private static func field(in view: NSView) -> LinkCursorTextField? {
        if let field = view as? LinkCursorTextField { return field }
        for subview in view.subviews {
            if let field = field(in: subview) { return field }
        }
        return nil
    }

    /// The link rects of the hosted body, in the host view, with y from the top.
    private func linkRects(in host: NSView) throws -> [CGRect] {
        let field = try #require(Self.field(in: host))
        return field.linkRects.map { rect in
            let converted = host.convert(rect, from: field)
            guard !host.isFlipped else { return converted }
            return CGRect(x: converted.minX, y: host.bounds.height - converted.maxY, width: converted.width, height: converted.height)
        }
    }

    private struct Bitmap {
        let rep: NSBitmapImageRep
        let scale: CGFloat

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

    // MARK: Rects

    /// A link on one line gets one rect, and a link that wraps gets one rect
    /// on each of its two lines. Each rect starts at the first glyph of the
    /// link on its line and ends at the last: the field draws ink at both
    /// ends inside the rect, and none in the space before or after it.
    @Test(arguments: Body.allCases)
    func eachLineOfALinkGetsARectOverItsText(body: Body) throws {
        let controller = hosted(body.html)
        let rects = try linkRects(in: controller.view)
        #expect(rects.count == body.lines)

        let bitmap = try render(controller.view)
        for rect in rects {
            #expect(rect.width > 10)
            // The x-height band of the line, above the underline and the
            // descenders.
            func band(from minX: CGFloat, to maxX: CGFloat) -> CGRect {
                CGRect(x: minX, y: rect.minY + rect.height * 0.35, width: maxX - minX, height: rect.height * 0.3)
            }
            #expect(bitmap.hasInk(in: band(from: rect.minX, to: rect.minX + 3)))
            #expect(bitmap.hasInk(in: band(from: rect.maxX - 3, to: rect.maxX)))
            #expect(!bitmap.hasInk(in: band(from: rect.maxX + 0.5, to: rect.maxX + 2.5)))
            #expect(!bitmap.hasInk(in: band(from: rect.minX - 2.5, to: rect.minX - 0.5)))
        }

        let field = try #require(Self.field(in: controller.view))
        let fieldFrame = controller.view.convert(field.bounds, from: field)
        if let first = rects.first {
            // "listen to " comes before the link on the first line.
            #expect(first.minX > fieldFrame.minX + 40)
        }
        if body == .wrapped {
            // The second part starts the second line, at the left of the text.
            #expect(rects[1].minY >= rects[0].maxY - 0.5)
            #expect(rects[1].minX <= fieldFrame.minX + LabelTextLayout.lineFragmentPadding + 0.5)
            #expect(rects[1].minX < rects[0].minX)
        }
    }

    /// The pointing hand inside a link rect, the I-beam outside of it.
    @Test(arguments: Body.allCases)
    func theCursorIsTheHandOverALinkAndTheIBeamElsewhere(body: Body) throws {
        let controller = hosted(body.html)
        let field = try #require(Self.field(in: controller.view))
        let rects = field.linkRects
        #expect(rects.count == body.lines)
        for rect in rects {
            #expect(field.cursor(at: NSPoint(x: rect.midX, y: rect.midY)) == NSCursor.pointingHand)
        }
        let first = try #require(rects.first)
        // "listen" before the link, on the same line.
        #expect(field.cursor(at: NSPoint(x: field.bounds.minX + 8, y: first.midY)) == NSCursor.iBeam)
    }

    /// The rects follow the field's width: the link that wraps at the test
    /// width takes one line in a wider field.
    @Test func theRectsFollowAWidthChange() {
        let string = AttributedTextView(attributedString: parseFormattedBody(Self.wrapped, baseFontSize: 13)).attributedString
        let field = LinkCursorTextField(labelWithAttributedString: string)
        field.frame = CGRect(x: 0, y: 0, width: Self.width, height: 60)
        #expect(field.linkRects.count == 2)
        field.frame = CGRect(x: 0, y: 0, width: 600, height: 20)
        #expect(field.linkRects.count == 1)
    }

    /// A mention is a link, and gets a rect.
    @Test func aMentionGetsARect() throws {
        let rects = try linkRects(in: hosted(Self.mention).view)
        #expect(rects.count == 1)
    }

    /// A marked music link has no `.link` (MATRIX-187). It gets one rect for
    /// each line of its glyph and text, on its click areas, which set the
    /// pointing hand themselves.
    @Test(arguments: Body.allCases)
    func aMusicLinkGetsARectOnEachClickArea(body: Body) throws {
        let controller = hosted(body.html.replacingOccurrences(of: Self.posted, with: Self.spotify), marksMusicLinks: true)
        let field = try #require(Self.field(in: controller.view))
        let rects = field.linkRects
        #expect(rects.count == body.lines)
        let targets = MusicLinkBar.targets(for: field.attributedStringValue, in: field.bounds)
        #expect(targets.map(\.rect) == rects)

        // The glyph comes before the text, so the rect starts before the bar.
        let bar = try #require(MusicLinkBar.rects(for: field.attributedStringValue, in: field.bounds).first)
        let first = try #require(rects.first)
        #expect(first.minX < bar.minX)
        #expect(abs(first.maxX - bar.maxX) < 0.5)
        #expect(field.cursor(at: NSPoint(x: first.midX, y: first.midY)) == NSCursor.pointingHand)
    }

    @Test func aBodyWithNoLinkHasNoRect() throws {
        let rects = try linkRects(in: hosted("<p>no link here</p>").view)
        #expect(rects.isEmpty)
    }

    // MARK: Mouse moves (MATRIX-214)

    /// A selectable field with the one-line link body, in a window that is
    /// not on screen.
    private func fieldInWindow() -> (window: NSWindow, field: LinkCursorTextField) {
        let string = AttributedTextView(attributedString: parseFormattedBody(Self.oneLine, baseFontSize: 13)).attributedString
        let field = LinkCursorTextField(labelWithAttributedString: string)
        field.isSelectable = true
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 40),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let container = NSView(frame: CGRect(x: 0, y: 0, width: Self.width, height: 40))
        window.contentView = container
        field.frame = container.bounds
        container.addSubview(field)
        return (window, field)
    }

    /// A mouseMoved event at `point` in the field's bounds. It has no
    /// tracking area: AppKit raises if the field reads one.
    private func mouseMoved(to point: NSPoint, in field: LinkCursorTextField) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: field.convert(point, to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: field.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ))
    }

    /// The field sets the cursor from the location of a mouseMoved event,
    /// and does not read the event's tracking area: the pointing hand over
    /// the link, the I-beam over other text.
    @Test func aMouseMoveSetsTheCursorFromItsLocation() throws {
        let (window, field) = fieldInWindow()
        defer { window.close() }
        let link = try #require(field.linkRects.first)

        try field.mouseMoved(with: mouseMoved(to: NSPoint(x: link.midX, y: link.midY), in: field))
        #expect(NSCursor.current == NSCursor.pointingHand)

        try field.mouseMoved(with: mouseMoved(to: NSPoint(x: field.bounds.minX + 8, y: link.midY), in: field))
        #expect(NSCursor.current == NSCursor.iBeam)
    }

    /// A view over the field, such as the timeline's hover action bar,
    /// keeps its cursor.
    @Test func aViewOverTheLinkKeepsTheCursor() throws {
        let (window, field) = fieldInWindow()
        defer { window.close() }
        let link = try #require(field.linkRects.first)
        let container = try #require(field.superview)
        container.addSubview(NSView(frame: container.convert(link, from: field)))

        NSCursor.arrow.set()
        try field.mouseMoved(with: mouseMoved(to: NSPoint(x: link.midX, y: link.midY), in: field))
        #expect(NSCursor.current == NSCursor.arrow)
    }

    /// While the field editor shows the text, the field leaves the cursor
    /// alone.
    @Test func theFieldEditorKeepsTheCursor() throws {
        let (window, field) = fieldInWindow()
        defer { window.close() }
        let link = try #require(field.linkRects.first)
        field.selectText(nil)
        try #require(field.currentEditor() != nil)

        NSCursor.arrow.set()
        try field.mouseMoved(with: mouseMoved(to: NSPoint(x: link.midX, y: link.midY), in: field))
        #expect(NSCursor.current == NSCursor.arrow)
    }
}

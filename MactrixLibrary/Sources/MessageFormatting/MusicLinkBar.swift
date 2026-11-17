import SwiftUI
#if canImport(AppKit)
    import AppKit
    import Tokens
#endif

extension NSAttributedString.Key {
    /// The text of a music link that draws the gradient bar (MATRIX-187).
    /// `MusicLinkMarker` sets it on macOS, `MusicLinkBar` reads it.
    static let musicLinkMarker = NSAttributedString.Key(rawValue: "MactrixMusicLinkMarker")

    /// The song.link URL of a music link's glyph and text on macOS
    /// (MATRIX-187). It takes the place of `.link`, which AppKit draws in the
    /// link color. `MusicLinkBar.targets` reads it for the click areas.
    static let musicLinkTarget = NSAttributedString.Key(rawValue: "MactrixMusicLinkTarget")
}

@MainActor
extension View {
    /// Draws the music link bar (MATRIX-187) behind this view, for the
    /// marked text of `string`, and puts a click area over each music link
    /// that opens its target. The view must be the `AttributedTextView`
    /// that shows `string`. Adds nothing for a string with no marked text,
    /// and nothing on iOS.
    @ViewBuilder
    func musicLinkBar(for string: NSAttributedString) -> some View {
        #if canImport(AppKit)
            if MusicLinkBar.hasMarker(string) {
                background(MusicLinkBarBackground(string: string).allowsHitTesting(false))
                    .overlay(MusicLinkTargets(string: string))
            } else {
                self
            }
        #else
            self
        #endif
    }
}

#if canImport(AppKit)
    /// The gradient bar at the bottom of a music link's text (MATRIX-187).
    ///
    /// The bar draws in a view behind the body's `NSTextField`, with the
    /// field's frame. The field stays as it is: a subclass of it that draws
    /// changes how AppKit renders all of its text. A SwiftUI background
    /// does not change the size of the view it is on, so a body with the bar
    /// has the height of the same body without it (MATRIX-153). It moves in
    /// the same layout pass and the same scroll as the text, and it takes no
    /// clicks.
    ///
    /// The bar sits in the descent area of each line,
    /// `MusicLinkToken.barDropScale` below the glyphs, but never below the
    /// line's used rect. Each line of a wrapped link gets its own full
    /// gradient, as CSS `box-decoration-break: clone` does.
    @MainActor
    enum MusicLinkBar {
        /// The line fragment padding of an `NSTextField` label cell. With it,
        /// a TextKit 1 stack as wide as the field breaks the lines where the
        /// cell breaks them, and puts each glyph where the cell draws it
        /// (`MusicLinkBarTests` checks this against the drawn pixels).
        static let labelLineFragmentPadding: CGFloat = 2

        /// True if `string` has text that draws the bar.
        static func hasMarker(_ string: NSAttributedString) -> Bool {
            var found = false
            string.enumerateAttribute(.musicLinkMarker, in: NSRange(location: 0, length: string.length)) { value, _, stop in
                if value != nil {
                    found = true
                    stop.pointee = true
                }
            }
            return found
        }

        /// The bar rects of `string`, laid out as an `NSTextField` label
        /// lays it out in `bounds` of a flipped view, one rect for each line
        /// of each marked range. Whitespace at the ends of a line gets no bar.
        static func rects(for string: NSAttributedString, in bounds: CGRect) -> [CGRect] {
            linePieces(of: .musicLinkMarker, in: string, width: bounds.width).map { piece in
                let font = string.attribute(.font, at: piece.chars.location, effectiveRange: nil) as? NSFont
                    ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                let bottom = min(
                    piece.usedRect.maxY,
                    piece.baseline - font.descender + font.pointSize * MusicLinkToken.barDropScale
                )
                return CGRect(
                    x: bounds.minX + piece.box.minX,
                    y: bounds.minY + bottom - MusicLinkToken.barThickness,
                    width: piece.box.width,
                    height: MusicLinkToken.barThickness
                )
            }
        }

        /// One click area of a music link.
        struct Target {
            let rect: CGRect
            let url: URL
            /// The link text on the area's line, without the glyph.
            let text: String
        }

        /// The click areas of the music links of `string`, laid out as for
        /// `rects(for:in:)`: one rect for each line of each link, glyph and
        /// text, as tall as the line. Each opens the link's song.link URL.
        static func targets(for string: NSAttributedString, in bounds: CGRect) -> [Target] {
            let all = string.string as NSString
            return linePieces(of: .musicLinkTarget, in: string, width: bounds.width).compactMap { piece in
                guard let url = piece.value as? URL else { return nil }
                let text = all.substring(with: piece.chars)
                    .replacingOccurrences(of: "\u{FFFC}", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return Target(rect: piece.box.offsetBy(dx: bounds.minX, dy: bounds.minY), url: url, text: text)
            }
        }

        /// The bounds of the `NSTextField` label in a view with the field's
        /// layout frame, `size`. SwiftUI gives the field and that view the
        /// same layout frame, and the field's frame is the layout frame grown
        /// by its alignment insets.
        static func fieldBounds(for size: CGSize) -> CGRect {
            let insets = labelInsets
            return CGRect(
                x: -insets.left,
                y: -insets.top,
                width: size.width + insets.left + insets.right,
                height: size.height + insets.top + insets.bottom
            )
        }

        /// The alignment insets of an `NSTextField` label.
        private static let labelInsets = NSTextField(labelWithString: "").alignmentRectInsets

        /// One line's part of a range that has an attribute, in the
        /// coordinates of the text container, which starts at the field's
        /// top left.
        private struct LinePiece {
            let value: Any
            let chars: NSRange
            let box: CGRect
            let usedRect: CGRect
            let baseline: CGFloat
        }

        /// Lays out `string` as the label cell lays it out at `width`, and
        /// returns each line's part of each range that has `key`. Whitespace
        /// at the ends of a line is not part of a piece.
        private static func linePieces(of key: NSAttributedString.Key, in string: NSAttributedString, width: CGFloat) -> [LinePiece] {
            var ranges: [(range: NSRange, value: Any)] = []
            let all = NSRange(location: 0, length: string.length)
            string.enumerateAttribute(key, in: all) { value, range, _ in
                if let value {
                    ranges.append((range, value))
                }
            }
            guard !ranges.isEmpty, width > 0 else { return [] }

            let storage = NSTextStorage(attributedString: string)
            let layoutManager = NSLayoutManager()
            let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = labelLineFragmentPadding
            layoutManager.addTextContainer(container)
            storage.addLayoutManager(layoutManager)

            let text = string.string as NSString
            var pieces: [LinePiece] = []
            for (range, value) in ranges {
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, usedRect, _, lineGlyphs, _ in
                    let lineChars = layoutManager.characterRange(
                        forGlyphRange: NSIntersectionRange(lineGlyphs, glyphs),
                        actualGlyphRange: nil
                    )
                    let chars = trimmingWhitespace(lineChars, in: text)
                    guard chars.length > 0 else { return }
                    let partGlyphs = layoutManager.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
                    pieces.append(LinePiece(
                        value: value,
                        chars: chars,
                        box: layoutManager.boundingRect(forGlyphRange: partGlyphs, in: container),
                        usedRect: usedRect,
                        baseline: lineRect.minY + layoutManager.location(forGlyphAt: partGlyphs.location).y
                    ))
                }
            }
            return pieces
        }

        /// Fills each rect with the full gradient, left to right.
        static func draw(_ rects: [CGRect]) {
            let stops = MusicLinkToken.barStops
            let locations = stops.map(\.location)
            guard !rects.isEmpty,
                  let gradient = NSGradient(colors: stops.map(\.color), atLocations: locations, colorSpace: .sRGB)
            else { return }
            for rect in rects {
                gradient.draw(in: rect, angle: 0)
            }
        }

        private static func trimmingWhitespace(_ range: NSRange, in text: NSString) -> NSRange {
            var start = range.location
            var end = range.location + range.length
            let whitespace = CharacterSet.whitespacesAndNewlines
            while start < end, let scalar = Unicode.Scalar(text.character(at: start)), whitespace.contains(scalar) {
                start += 1
            }
            while end > start, let scalar = Unicode.Scalar(text.character(at: end - 1)), whitespace.contains(scalar) {
                end -= 1
            }
            return NSRange(location: start, length: end - start)
        }
    }

    /// The view behind the body's text field that draws the bar.
    final class MusicLinkBarView: NSView {
        var string = NSAttributedString() {
            didSet {
                if string != oldValue {
                    needsDisplay = true
                }
            }
        }

        override var isFlipped: Bool { true }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            needsDisplay = true
        }

        override func draw(_: NSRect) {
            let fieldBounds = MusicLinkBar.fieldBounds(for: bounds.size).offsetBy(dx: bounds.minX, dy: bounds.minY)
            MusicLinkBar.draw(MusicLinkBar.rects(for: string, in: fieldBounds))
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }

    private struct MusicLinkBarBackground: NSViewRepresentable {
        let string: NSAttributedString

        func makeNSView(context _: Context) -> MusicLinkBarView {
            let view = MusicLinkBarView()
            view.string = string
            return view
        }

        func updateNSView(_ view: MusicLinkBarView, context _: Context) {
            view.string = string
        }
    }

    /// The click areas over the music links (MATRIX-187). The link text
    /// has no `.link`, so the text field does not open it. A click in an
    /// area opens the link's song.link URL. Outside the areas, the clicks go
    /// to the text field, so its text stays selectable. A right click goes
    /// to the row, which shows the message menu.
    struct MusicLinkTargets: View {
        let string: NSAttributedString
        @Environment(\.openURL) private var openURL

        var body: some View {
            GeometryReader { proxy in
                let targets = MusicLinkBar.targets(for: string, in: MusicLinkBar.fieldBounds(for: proxy.size))
                ForEach(targets.indices, id: \.self) { index in
                    let target = targets[index]
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: target.rect.width, height: target.rect.height)
                        .position(x: target.rect.midX, y: target.rect.midY)
                        .onTapGesture { openURL(target.url) }
                        .pointerStyle(.link)
                        .accessibilityElement()
                        .accessibilityAddTraits(.isLink)
                        .accessibilityLabel(target.text)
                }
            }
        }
    }
#endif

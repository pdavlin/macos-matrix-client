import SwiftUI
#if canImport(AppKit)
    import AppKit
    import Tokens
#endif

extension NSAttributedString.Key {
    /// The text of a music link that draws the gradient bar (MATRIX-187).
    /// `MusicLinkMarker` sets it on macOS, `MusicLinkBar` reads it.
    static let musicLinkMarker = NSAttributedString.Key(rawValue: "MactrixMusicLinkMarker")
}

@MainActor
extension View {
    /// Draws the music link bar (MATRIX-187) behind this view, for the
    /// marked text of `string`. The view must be the `AttributedTextView`
    /// that shows `string`. Adds nothing for a string with no marked text,
    /// and nothing on iOS.
    @ViewBuilder
    func musicLinkBar(for string: NSAttributedString) -> some View {
        #if canImport(AppKit)
            if MusicLinkBar.hasMarker(string) {
                background(MusicLinkBarBackground(string: string).allowsHitTesting(false))
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
            var marked: [NSRange] = []
            string.enumerateAttribute(.musicLinkMarker, in: NSRange(location: 0, length: string.length)) { value, range, _ in
                if value != nil {
                    marked.append(range)
                }
            }
            guard !marked.isEmpty, bounds.width > 0 else { return [] }

            let storage = NSTextStorage(attributedString: string)
            let layoutManager = NSLayoutManager()
            let container = NSTextContainer(size: CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = labelLineFragmentPadding
            layoutManager.addTextContainer(container)
            storage.addLayoutManager(layoutManager)

            let text = string.string as NSString
            var rects: [CGRect] = []
            for range in marked {
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, usedRect, _, lineGlyphs, _ in
                    let lineChars = layoutManager.characterRange(
                        forGlyphRange: NSIntersectionRange(lineGlyphs, glyphs),
                        actualGlyphRange: nil
                    )
                    let chars = trimmingWhitespace(lineChars, in: text)
                    guard chars.length > 0 else { return }
                    let partGlyphs = layoutManager.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
                    let box = layoutManager.boundingRect(forGlyphRange: partGlyphs, in: container)
                    let font = string.attribute(.font, at: chars.location, effectiveRange: nil) as? NSFont
                        ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                    let baseline = lineRect.minY + layoutManager.location(forGlyphAt: partGlyphs.location).y
                    let bottom = min(
                        usedRect.maxY,
                        baseline - font.descender + font.pointSize * MusicLinkToken.barDropScale
                    )
                    rects.append(CGRect(
                        x: bounds.minX + box.minX,
                        y: bounds.minY + bottom - MusicLinkToken.barThickness,
                        width: box.width,
                        height: MusicLinkToken.barThickness
                    ))
                }
            }
            return rects
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

        /// The alignment insets of an `NSTextField` label. SwiftUI gives the
        /// field and this view the same layout frame, and the field's frame
        /// is the layout frame grown by these insets.
        private static let labelInsets = NSTextField(labelWithString: "").alignmentRectInsets

        override func draw(_: NSRect) {
            let insets = Self.labelInsets
            let fieldBounds = NSRect(
                x: bounds.minX - insets.left,
                y: bounds.minY - insets.top,
                width: bounds.width + insets.left + insets.right,
                height: bounds.height + insets.top + insets.bottom
            )
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
#endif

#if canImport(AppKit)
    import AppKit

    /// The line layout of the text in an `NSTextField` label, from a TextKit 1
    /// stack that breaks the lines where the label cell breaks them. The music
    /// link bar and click areas (MATRIX-187) and the link cursor (MATRIX-190)
    /// use it.
    @MainActor
    enum LabelTextLayout {
        /// The line fragment padding of an `NSTextField` label cell. With it,
        /// a TextKit 1 stack as wide as the field breaks the lines where the
        /// cell breaks them, and puts each glyph where the cell draws it
        /// (`MusicLinkBarTests` checks this against the drawn pixels).
        static let lineFragmentPadding: CGFloat = 2

        /// One line's part of a range that has an attribute.
        struct LinePart {
            /// The value of the attribute.
            let value: Any
            /// The characters of the range on the line, without whitespace
            /// at the ends of the line.
            let characters: NSRange
            /// The bounding rect of those characters.
            let box: CGRect
            /// The used rect of the line.
            let usedRect: CGRect
            /// The y of the baseline under the first of those characters.
            let baseline: CGFloat
        }

        /// Lays out `string` as an `NSTextField` label `width` wide lays it
        /// out, and returns each line's part of each range that has one of
        /// `keys`. The rects are in the coordinates of the text container,
        /// which starts at the field's top left, with y down. A line with only
        /// whitespace of a range gets no part.
        static func lineParts(
            of keys: [NSAttributedString.Key],
            in string: NSAttributedString,
            width: CGFloat
        ) -> [LinePart] {
            var ranges: [(range: NSRange, value: Any)] = []
            let all = NSRange(location: 0, length: string.length)
            for key in keys {
                // Without options, each range is the longest run of one value.
                string.enumerateAttribute(key, in: all) { value, range, _ in
                    if let value {
                        ranges.append((range, value))
                    }
                }
            }
            guard !ranges.isEmpty, width > 0 else { return [] }

            let storage = NSTextStorage(attributedString: string)
            let layoutManager = NSLayoutManager()
            let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = lineFragmentPadding
            layoutManager.addTextContainer(container)
            storage.addLayoutManager(layoutManager)

            let text = string.string as NSString
            var parts: [LinePart] = []
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
                    parts.append(LinePart(
                        value: value,
                        characters: chars,
                        box: layoutManager.boundingRect(forGlyphRange: partGlyphs, in: container),
                        usedRect: usedRect,
                        baseline: lineRect.minY + layoutManager.location(forGlyphAt: partGlyphs.location).y
                    ))
                }
            }
            return parts
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
#endif

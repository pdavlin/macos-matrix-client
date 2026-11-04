#if os(macOS)
    import AppKit
    import Models
    import Tokens

    /// A mention chip in the Mac composer (MATRIX-105, D-6).
    ///
    /// The chip is a text attachment, so the text storage holds it as one
    /// object replacement character (U+FFFC). That makes it atomic with no
    /// custom editing code: the caret cannot go inside one character, one
    /// Backspace deletes it, and the user cannot edit its label.
    ///
    /// The cell draws the chip in TextKit 1. The composer text view uses
    /// TextKit 1 (`NSTextView(usingTextLayoutManager: false)`).
    public final class MentionChipAttachment: NSTextAttachment {
        /// The user this chip mentions.
        public let mention: MentionTarget

        @MainActor
        public init(mention: MentionTarget) {
            self.mention = mention
            super.init(data: nil, ofType: nil)
            attachmentCell = MentionChipAttachmentCell(label: "@" + mention.label)
        }

        /// Chips are not decoded. The composer pasteboard carries draft text
        /// (see `DynamicTextView`), and undo keeps the live objects, so no
        /// path archives a chip. Failing here drops the character instead of
        /// a crash.
        required init?(coder _: NSCoder) {
            return nil
        }
    }

    /// Draws a chip: a capsule in the accent color with "@label" inside.
    ///
    /// The size comes from the font at the chip's character, so a font size
    /// change in Settings resizes chips with the text around them.
    final class MentionChipAttachmentCell: NSTextAttachmentCell {
        let label: String

        init(label: String) {
            self.label = label
            super.init(textCell: "")
        }

        /// Required by `NSCell`. Chips are not archived (see
        /// `MentionChipAttachment.init(coder:)`); a decoded cell draws an
        /// empty capsule.
        required init(coder: NSCoder) {
            label = ""
            super.init(coder: coder)
        }

        /// The font of the text at `characterIndex`, or the system font.
        private nonisolated static func font(at characterIndex: Int, in storage: NSTextStorage?) -> NSFont {
            guard let storage, characterIndex < storage.length,
                  let font = storage.attribute(.font, at: characterIndex, effectiveRange: nil) as? NSFont
            else {
                return NSFont.systemFont(ofSize: NSFont.systemFontSize)
            }
            return font
        }

        /// The chip size for a font.
        private nonisolated static func chipSize(for font: NSFont, label: String) -> NSSize {
            let labelSize = (label as NSString).size(withAttributes: [.font: font])
            return NSSize(
                width: ceil(labelSize.width) + 2 * MentionToken.chipHorizontalPadding,
                height: ceil(font.ascender - font.descender) + 2 * MentionToken.chipVerticalPadding
            )
        }

        override func cellSize() -> NSSize {
            Self.chipSize(for: Self.font(at: 0, in: nil), label: label)
        }

        override func cellBaselineOffset() -> NSPoint {
            let font = Self.font(at: 0, in: nil)
            return NSPoint(x: 0, y: font.descender - MentionToken.chipVerticalPadding)
        }

        override func cellFrame(
            for textContainer: NSTextContainer,
            proposedLineFragment _: NSRect,
            glyphPosition _: NSPoint,
            characterIndex charIndex: Int
        ) -> NSRect {
            let font = Self.font(at: charIndex, in: unsafe textContainer.layoutManager?.textStorage)
            let size = Self.chipSize(for: font, label: label)
            // The origin is relative to the baseline: start below it by the
            // font descender, so the label baseline lines up with the text.
            return NSRect(x: 0, y: font.descender - MentionToken.chipVerticalPadding, width: size.width, height: size.height)
        }

        override func draw(
            withFrame cellFrame: NSRect,
            in _: NSView?,
            characterIndex charIndex: Int,
            layoutManager: NSLayoutManager
        ) {
            let font = Self.font(at: charIndex, in: unsafe layoutManager.textStorage)
            let capsule = NSBezierPath(
                roundedRect: cellFrame,
                xRadius: cellFrame.height / 2,
                yRadius: cellFrame.height / 2
            )
            NSColor.controlAccentColor.withAlphaComponent(MentionToken.chipBackgroundOpacity).setFill()
            capsule.fill()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.controlAccentColor
            ]
            let labelSize = (label as NSString).size(withAttributes: attributes)
            let origin = NSPoint(
                x: cellFrame.minX + MentionToken.chipHorizontalPadding,
                y: cellFrame.midY - labelSize.height / 2
            )
            (label as NSString).draw(at: origin, withAttributes: attributes)
        }

        override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
            guard let textView = controlView as? NSTextView, let layoutManager = unsafe textView.layoutManager else { return }
            draw(withFrame: cellFrame, in: controlView, characterIndex: 0, layoutManager: layoutManager)
        }

        override func wantsToTrackMouse() -> Bool {
            false
        }
    }

    /// Converts between the composer's attributed text and its segments.
    @MainActor
    public enum ComposerAttributedText {
        /// The attributed string for some segments.
        ///
        /// - Parameters:
        ///   - segments: the composer content.
        ///   - attributes: the font and color for text and chips.
        /// - Returns: text runs, and one attachment character for each chip.
        public static func attributedString(
            for segments: [ComposerSegment],
            attributes: [NSAttributedString.Key: Any]
        ) -> NSAttributedString {
            let result = NSMutableAttributedString()
            for segment in segments {
                switch segment {
                case let .text(text):
                    result.append(NSAttributedString(string: text, attributes: attributes))
                case let .mention(target):
                    result.append(chip(for: target, attributes: attributes))
                }
            }
            return result
        }

        /// One chip, as the attributed string to insert.
        public static func chip(
            for target: MentionTarget,
            attributes: [NSAttributedString.Key: Any]
        ) -> NSAttributedString {
            let chip = NSMutableAttributedString(attachment: MentionChipAttachment(mention: target))
            chip.addAttributes(attributes, range: NSRange(location: 0, length: chip.length))
            return chip
        }

        /// The segments for an attributed string.
        ///
        /// An attachment that is not a chip (for example a pasted image) is
        /// left out, because the composer sends text only.
        public static func segments(from attributed: NSAttributedString) -> [ComposerSegment] {
            var segments: [ComposerSegment] = []
            let text = attributed.string as NSString
            var pendingText = ""

            func flushText() {
                guard !pendingText.isEmpty else { return }
                segments.append(.text(pendingText))
                pendingText = ""
            }

            attributed.enumerateAttribute(
                .attachment,
                in: NSRange(location: 0, length: attributed.length)
            ) { value, range, _ in
                guard let attachment = value as? NSTextAttachment else {
                    pendingText += text.substring(with: range)
                    return
                }
                guard let chip = attachment as? MentionChipAttachment else { return }
                flushText()
                // One attachment object covers one character. A longer run is
                // the same chip repeated; keep each character.
                for _ in 0 ..< range.length {
                    segments.append(.mention(chip.mention))
                }
            }
            flushText()
            return segments
        }
    }
#endif

#if canImport(AppKit)
    import AppKit

    /// The `NSTextField` of a message body (`AttributedTextView`). Over the
    /// text of a link the pointer is the pointing hand. Over other text it
    /// stays the I-beam, and the text stays selectable (MATRIX-190).
    ///
    /// A selectable label adds one I-beam cursor rect for all of its bounds,
    /// links included. The field keeps that rect, so the pointer gets the
    /// I-beam on entry and the arrow on exit as before. A tracking area in the
    /// field's visible rect then sets the cursor on each move from the link
    /// rects, which come from `LabelTextLayout` for the current bounds and
    /// string. The area follows the visible rect through scroll and resize,
    /// so no cursor rect must be invalidated. The link rects are made again
    /// when the size or the string changes. Nothing draws, and the size does
    /// not change.
    ///
    /// A marked music link has no `.link`. Its click areas (`MusicLinkTargets`)
    /// lie over the field and set the pointing hand with `.pointerStyle(.link)`.
    /// The field sets the cursor only where it is the view under the pointer,
    /// so it leaves those areas, and the timeline's hover action bar, alone.
    ///
    /// While the field editor shows the text (after a click or a selection),
    /// the field does nothing. The field editor is an `NSTextView`, which
    /// shows the pointing hand over links itself.
    public final class LinkCursorTextField: NSTextField {
        private var linkArea: NSTrackingArea?
        private var linkRectsCache: (size: CGSize, rects: [CGRect])?

        override public var attributedStringValue: NSAttributedString {
            didSet {
                linkRectsCache = nil
            }
        }

        /// The rects of the link text, in the field's bounds, one for each
        /// line of each link.
        var linkRects: [CGRect] {
            if let linkRectsCache, linkRectsCache.size == bounds.size {
                return linkRectsCache.rects
            }
            let rects = Self.linkRects(for: attributedStringValue, in: bounds, isFlipped: isFlipped)
            linkRectsCache = (bounds.size, rects)
            return rects
        }

        /// The cursor at `point`, in the field's bounds.
        func cursor(at point: NSPoint) -> NSCursor {
            linkRects.contains { $0.contains(point) } ? .pointingHand : .iBeam
        }

        /// The rects of the link text of `string`, laid out as a label lays
        /// it out in `bounds`. One rect for each line of each link: a plain
        /// link and a mention (`.link`), and a marked music link with its
        /// glyph (`.musicLinkTarget`, MATRIX-187).
        static func linkRects(for string: NSAttributedString, in bounds: CGRect, isFlipped: Bool) -> [CGRect] {
            let parts = LabelTextLayout.lineParts(of: [.link, .musicLinkTarget], in: string, width: bounds.width)
            return parts.map { part in
                let y = isFlipped ? bounds.minY + part.box.minY : bounds.maxY - part.box.maxY
                return CGRect(x: bounds.minX + part.box.minX, y: y, width: part.box.width, height: part.box.height)
            }
        }

        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard linkArea == nil else { return }
            // `inVisibleRect` ignores the rect and follows the visible rect.
            let area = NSTrackingArea(
                rect: .zero,
                options: [.cursorUpdate, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            linkArea = area
        }

        override public func cursorUpdate(with event: NSEvent) {
            guard currentEditor() == nil, isHit(by: event) else {
                super.cursorUpdate(with: event)
                return
            }
            cursor(at: convert(event.locationInWindow, from: nil)).set()
        }

        override public func mouseMoved(with event: NSEvent) {
            guard let linkArea, event.trackingArea === linkArea else {
                super.mouseMoved(with: event)
                return
            }
            guard currentEditor() == nil, isHit(by: event) else { return }
            cursor(at: convert(event.locationInWindow, from: nil)).set()
        }

        /// True if the field is the view under the pointer: no view above it,
        /// such as the timeline's hover action bar, covers the point.
        private func isHit(by event: NSEvent) -> Bool {
            guard let root = window?.contentView else { return false }
            let point = root.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            return root.hitTest(point) === self
        }
    }
#endif

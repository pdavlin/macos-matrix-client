import SwiftUI

#if os(macOS)
    import AppKit

    /// The view that carries a reaction chip's tooltip (MATRIX-166).
    ///
    /// AppKit shows `toolTip` when the pointer rests in the view's frame. The
    /// view draws nothing and never takes a hit test, so a click goes to the
    /// chip under it and the pointer tracking of the timeline's hover bar
    /// (MATRIX-145) is not affected: a tooltip uses its own tracking rect.
    public final class ReactionChipToolTipView: NSView {
        override public func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        override public var acceptsFirstResponder: Bool {
            false
        }
    }

    /// Puts an AppKit tooltip over a SwiftUI view.
    ///
    /// The timeline hosts each row in an `NSHostingView` inside a table. A
    /// plain `NSView` with `toolTip` is the system's own tooltip path, with
    /// the system's delay, placement, and dismissal on scroll or click, and
    /// does not depend on how SwiftUI's `.help` works under a custom button
    /// style inside a hosted row.
    struct ReactionChipToolTipArea: NSViewRepresentable {
        let text: String

        func makeNSView(context _: Context) -> ReactionChipToolTipView {
            let view = ReactionChipToolTipView()
            view.setAccessibilityElement(false)
            return view
        }

        func updateNSView(_ view: ReactionChipToolTipView, context _: Context) {
            let toolTip = text.isEmpty ? nil : text
            if view.toolTip != toolTip {
                view.toolTip = toolTip
            }
        }
    }
#endif

extension View {
    /// Shows `text` as the system tooltip of a reaction chip on the Mac. An
    /// overlay, so it never changes the chip's size. Other platforms have no
    /// tooltip; the chip's accessibility label carries the same people.
    @ViewBuilder
    func reactionChipToolTip(_ text: String) -> some View {
        #if os(macOS)
            overlay {
                ReactionChipToolTipArea(text: text)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        #else
            self
        #endif
    }
}

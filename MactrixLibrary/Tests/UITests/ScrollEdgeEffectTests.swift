import AppKit
import SwiftUI
import Testing
import UI

/// The label rail sets the soft scroll edge effect on its AppKit scroll view
/// (MATRIX-196).
///
/// The system effect needs a window titlebar over the scroll view, so an
/// offscreen snapshot does not show it. This test reads the style that
/// SwiftUI gives the hosted `NSScrollView` instead. AppKit has no public
/// getter for it, so the test reads the private `scrollPocketStyleOnEdge:`
/// (0 is the top edge; 0 automatic, 1 soft, 2 hard). If a later macOS removes
/// that selector, the test passes without the check and prints a note.
@MainActor
struct ScrollEdgeEffectTests {
    private static let styleSelector = NSSelectorFromString("scrollPocketStyleOnEdge:")
    private static let topEdge = 0
    private static let softStyle = 1

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    private func topStyle(of scrollView: NSScrollView) -> Int? {
        guard let method = class_getInstanceMethod(NSScrollView.self, Self.styleSelector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector, Int) -> Int
        let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        return getter(scrollView, Self.styleSelector, Self.topEdge)
    }

    @Test func theLabelRailScrollViewHasTheSoftTopEdge() throws {
        let rail = LabelRail(labels: [], selection: .inbox, actions: .none)
            .frame(height: 300)
        let host = NSHostingView(rootView: rail)
        host.frame.size = host.fittingSize
        _ = ScaledImageSnapshotting.render(host, scale: 1)
        let scrollView = try #require(firstScrollView(in: host))
        guard let style = topStyle(of: scrollView) else {
            print("scrollPocketStyleOnEdge: is gone; the scroll edge style is not checked")
            return
        }
        #expect(style == Self.softStyle)
    }
}

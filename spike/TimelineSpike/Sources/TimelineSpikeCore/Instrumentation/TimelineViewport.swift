import AppKit

/// Locates the timeline's scroll view without knowing which renderer built it.
///
/// Row heights are cached per width, so the width the rows lay out at is an input to every
/// frame number a dump carries. It has to be read back from the live view rather than assumed
/// from a constant, which is what this exists for.
@MainActor
public enum TimelineViewport {
    /// Clip-view size of the timeline scroll view, or `.zero` when no window is up.
    public static func currentSize() -> CGSize {
        scrollView()?.contentSize ?? .zero
    }

    /// The first scroll view found depth-first in the first window.
    ///
    /// `HarnessRootView` puts the timeline pane before the control panel, so the first hit is
    /// the timeline's in every renderer.
    public static func scrollView() -> NSScrollView? {
        guard let contentView = NSApplication.shared.windows.first?.contentView else { return nil }
        return firstScrollView(in: contentView)
    }

    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }
}

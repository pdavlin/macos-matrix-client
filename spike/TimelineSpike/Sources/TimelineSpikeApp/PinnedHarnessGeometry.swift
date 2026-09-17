import AppKit

/// Window and pane geometry the automated gate runs under.
///
/// The `Window(id: "timeline-spike")` scene is restorable, so AppKit reopens it at whatever
/// frame the previous session left in `NSWindow Frame timeline-spike`. A stale off-screen
/// frame clamps differently on each launch, and because row heights are cached per width, the
/// width that fell out of that clamp moved every frame number the gate recorded. Under
/// `--scenario` the harness ignores the saved frame and applies these values instead, so a
/// gate run measures the same layout every time.
enum PinnedHarnessGeometry {
    /// Defaults key AppKit uses for the scene's restorable frame.
    static let savedFrameKey = "NSWindow Frame timeline-spike"

    /// Pinned window frame size. Fits inside a 1512x949 visible frame, the smallest display
    /// the gate is run on.
    static let windowSize = CGSize(width: 1472, height: 938)

    /// Width of the control panel column in `HarnessRootView`.
    static let controlPanelWidth: CGFloat = 340

    /// Width the timeline pane is pinned to: the window width less the control panel and the
    /// divider between them.
    ///
    /// Pinned in the layout as well as through the window frame, because the pane width is
    /// what the height cache keys on. A hard frame keeps the pane exact even if the window
    /// cannot get the size it asked for. The clip view inside the pane is narrower than this
    /// by the vertical scroller's inset — 17pt when the display style is legacy rather than
    /// overlay — so the number the gate pins is `SpikeReport.timelineWidth`, measured from the
    /// live clip view, not this constant.
    static let timelinePaneWidth: CGFloat = windowSize.width - controlPanelWidth - 1

    /// Height the timeline pane is pinned to.
    ///
    /// Pinned for the same reason the width is, and it was missed for longer: viewport height
    /// sets how many rows a frame draws, so it is an input to every frame number the gate
    /// records. Clamping the window is not enough — SwiftUI gives the pane its content's ideal
    /// height and lets the window clip it, so the clip view can be 1327pt tall inside a 938pt
    /// window and the log still reports the pinned frame. On the 1512x949 laptop panel the
    /// screen clamped the whole thing back to ~906pt and the gap never showed; on a 2560x1440
    /// display it recorded 47% more rows per frame against a 906pt baseline.
    ///
    /// 906 is what the pane resolved to inside the pinned window on the reference laptop
    /// panel, which is the height every pre-existing dump was measured at.
    static let timelinePaneHeight: CGFloat = 906

    /// True when the process was launched by the gate driver.
    static var isDriverRun: Bool {
        CommandLine.arguments.contains("--scenario")
    }

    /// Drops the restorable frame so the scene cannot reopen at a stale one.
    ///
    /// Call before the scene builds its window. `run-gate.sh` removes the same key before
    /// launch; both layers exist so a run started by hand from `GATE.md` is as deterministic
    /// as one started by the script.
    static func clearSavedFrame() {
        UserDefaults.standard.removeObject(forKey: savedFrameKey)
    }

    /// Waits for the scene's window, then pins it.
    ///
    /// Applied twice: SwiftUI can set the scene's own frame after the first call.
    @MainActor
    static func pinWindow() async {
        for _ in 0 ..< 40 {
            if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
                apply(to: window)
                try? await Task.sleep(nanoseconds: 250_000_000)
                apply(to: window)
                print("[TimelineSpike] pinned window frame: \(NSStringFromRect(window.frame))")
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        print("[TimelineSpike] no window to pin — this run's geometry is not deterministic")
    }

    /// Places the window at `windowSize`, centred horizontally under the top of the visible
    /// frame, and stops the run writing a frame back for the next one to restore.
    ///
    /// The size is clamped as well as set. Setting the frame alone is not enough: SwiftUI
    /// sizes the scene to its content's ideal height after this runs, and the timeline pane
    /// has a pinned width but no height constraint, so the window grows to whatever the
    /// content asks for. On the 1512x949 laptop panel the screen clamped that back to ~938
    /// and hid the problem; on a 2560x1440 display it did not, and the gate recorded a 1327pt
    /// viewport against a baseline measured at 906pt — 47% more rows drawn per frame, on a
    /// window the log still reported as 1472x938. Viewport height is an input to frame cost
    /// exactly as width is, so it is pinned, not merely observed.
    @MainActor
    private static func apply(to window: NSWindow) {
        _ = window.setFrameAutosaveName("")
        window.isRestorable = false
        window.contentMinSize = windowSize
        window.contentMaxSize = windowSize
        window.minSize = windowSize
        window.maxSize = windowSize
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else {
            window.setFrame(NSRect(origin: .zero, size: windowSize), display: true)
            return
        }
        let origin = NSPoint(
            x: (visible.minX + (visible.width - windowSize.width) / 2).rounded(),
            y: (visible.maxY - windowSize.height).rounded()
        )
        window.setFrame(NSRect(origin: origin, size: windowSize), display: true)
    }
}

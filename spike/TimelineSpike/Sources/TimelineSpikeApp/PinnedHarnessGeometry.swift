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
    @MainActor
    private static func apply(to window: NSWindow) {
        _ = window.setFrameAutosaveName("")
        window.isRestorable = false
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

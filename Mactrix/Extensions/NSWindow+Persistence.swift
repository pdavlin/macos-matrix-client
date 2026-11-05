import AppKit
import SwiftUI

extension NSApplication {
    /// The frontmost main (sidebar) window, if one is open.
    ///
    /// SwiftUI names the windows of `WindowGroup(id: "main")`
    /// `main-AppWindow-<n>`. The ⌘T "New Tab" command finds them the same
    /// way.
    var frontmostMainWindow: NSWindow? {
        orderedWindows.first { window in
            window.identifier?.rawValue.hasPrefix("main-AppWindow") ?? false
        }
    }
}

/// Saves a window's frame under a name of its own and restores it when the
/// window opens again (MATRIX-116).
///
/// SwiftUI already saves each window's frame under the window's identifier
/// (`NSWindow Frame <scene id>-AppWindow-<n>` in the app's defaults), and
/// scene restoration puts every restored window back at its frame. That
/// identifier counts windows, so a single-room window opened later would
/// take the frame of whichever room window had its number before. Put this
/// in the window's background with a per-room name, and the room opens
/// where the user left it.
///
/// ```swift
/// RoomWindowView(roomId: roomId)
///     .background(WindowFrameAutosave(name: "RoomWindow \(roomId)"))
/// ```
struct WindowFrameAutosave: NSViewRepresentable {
    /// The defaults name. One window at a time can hold a name; AppKit
    /// ignores a second window that asks for it.
    let name: String

    func makeNSView(context _: Context) -> AutosaveView {
        AutosaveView(name: name)
    }

    func updateNSView(_ view: AutosaveView, context _: Context) {
        view.name = name
    }

    final class AutosaveView: NSView {
        var name: String {
            didSet {
                if name != oldValue { applyToWindow() }
            }
        }

        init(name: String) {
            self.name = name
            super.init(frame: .zero)
        }

        required init?(coder _: NSCoder) {
            return nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyToWindow()
        }

        /// Restores the saved frame, if any, then saves under `name` from
        /// now on. It runs one turn later, because SwiftUI sizes a new
        /// window after it inserts the window's content.
        private func applyToWindow() {
            guard window != nil else { return }
            Task { @MainActor [weak self] in
                guard let self, let window = self.window, window.frameAutosaveName != self.name else { return }
                window.setFrameUsingName(self.name)
                window.setFrameAutosaveName(self.name)
            }
        }
    }
}

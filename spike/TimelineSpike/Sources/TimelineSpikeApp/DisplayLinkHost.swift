import AppKit
import SwiftUI
import TimelineSpikeCore

/// A zero-size AppKit view whose only job is to give `FrameRecorder` something to hang a
/// `CADisplayLink` on.
///
/// The link must come from a view that is already in a window, so attachment happens in
/// `viewDidMoveToWindow` rather than in `makeNSView`.
struct DisplayLinkHost: NSViewRepresentable {
    let harness: SpikeHarness

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.onEnterWindow = { [harness] hostView in
            harness.attachDisplayLink(to: hostView)
        }
        view.onLeaveWindow = { [harness] in
            harness.detachDisplayLink()
        }
        return view
    }

    func updateNSView(_ nsView: HostView, context: Context) {}

    final class HostView: NSView {
        var onEnterWindow: ((HostView) -> Void)?
        var onLeaveWindow: (() -> Void)?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                onEnterWindow?(self)
            } else {
                onLeaveWindow?()
            }
        }
    }
}

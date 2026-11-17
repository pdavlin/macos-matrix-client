import AppKit
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshots of the notice above the main composer for a reply to a thread
/// that was not sent (MATRIX-173).
///
/// They check that the text and the three actions fit on one line at a
/// narrow main column, and that the line holds without Open Thread.
@MainActor
struct ThreadReplyNoticeSnapshotTests {
    private func host(_ view: some View, width: CGFloat) -> NSViewController {
        let controller = NSHostingController(rootView: view.frame(width: width))
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance, so the snapshot does not flip with dark mode.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func notice() {
        assertSnapshot(
            of: host(ThreadReplyNoticeView(retry: {}, openThread: {}, discard: {}), width: 420),
            as: .scaledImage
        )
    }

    /// A narrow main column: the text and the three actions stay on one
    /// line with no truncation.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func narrowColumn() {
        assertSnapshot(
            of: host(ThreadReplyNoticeView(retry: {}, openThread: {}, discard: {}), width: 340),
            as: .scaledImage
        )
    }

    /// The width the full line needs is less than the narrow column of the
    /// snapshot above, so that snapshot shows no truncated text.
    @Test func fullLineFitsNarrowColumn() {
        let controller = NSHostingController(rootView: ThreadReplyNoticeView(retry: {}, openThread: {}, discard: {}))
        #expect(controller.view.fittingSize.width <= 340)
    }

    /// A merged chat has no thread panel: no Open Thread.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func withoutOpenThread() {
        assertSnapshot(
            of: host(ThreadReplyNoticeView(retry: {}, openThread: nil, discard: {}), width: 420),
            as: .scaledImage
        )
    }
}

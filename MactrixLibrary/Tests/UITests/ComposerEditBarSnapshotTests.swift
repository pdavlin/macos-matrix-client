import AppKit
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshots of the composer's edit bar (MATRIX-109, M2-B2).
///
/// They check that the title, the one-line preview, and the cancel button
/// fit in a composer-wide bar, and that a long preview truncates instead of
/// wrapping.
@MainActor
struct ComposerEditBarSnapshotTests {
    private func host(_ view: some View) -> NSViewController {
        let controller = NSHostingController(rootView: view.frame(width: 420))
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance, so the snapshot does not flip with dark mode.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func shortPreview() {
        assertSnapshot(
            of: host(ComposerEditBar(previewText: "See you at 10", onCancel: {})),
            as: .scaledImage
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func longPreviewTruncates() {
        let preview = String(repeating: "A long message that does not fit on one line. ", count: 4)
        assertSnapshot(
            of: host(ComposerEditBar(previewText: preview, onCancel: {})),
            as: .scaledImage
        )
    }

    /// A media message with no caption: no preview line.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func noPreview() {
        assertSnapshot(
            of: host(ComposerEditBar(previewText: "", onCancel: {})),
            as: .scaledImage
        )
    }
}

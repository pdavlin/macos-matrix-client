import AppKit
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshots of the delete confirmation (MATRIX-110, M2-B3).
///
/// The sheet is the only thing between a click and a redaction for everyone,
/// so the snapshots check that Cancel is the default (prominent) button and
/// that the reason field and the note fit.
@MainActor
struct MessageRedactionSheetSnapshotTests {
    private func host(_ view: some View) -> NSViewController {
        let controller = NSHostingController(rootView: view)
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance, so the snapshot does not flip with dark mode.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func ownMessage() {
        assertSnapshot(
            of: host(MessageRedactionSheet(isOwn: true, onDelete: { _ in }, onCancel: {})),
            as: .scaledImage
        )
    }

    /// A moderator deletes another person's message: the note says so.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func otherPersonsMessage() {
        assertSnapshot(
            of: host(MessageRedactionSheet(isOwn: false, onDelete: { _ in }, onCancel: {})),
            as: .scaledImage
        )
    }
}

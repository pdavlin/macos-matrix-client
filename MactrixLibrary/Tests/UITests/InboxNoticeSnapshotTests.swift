import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-206: the note with Undo at the foot of the chat list.
@MainActor
struct InboxNoticeSnapshotTests {
    private func snapshot(of view: some View) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .padding(10)
                    .frame(width: 320)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func archivedNote() {
        assertSnapshot(of: snapshot(of: InboxNoticeToast(message: "Archived Alice") {}), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func longNameTruncates() {
        let toast = InboxNoticeToast(message: "Archived Release planning and the notarization queue backlog") {}
        assertSnapshot(of: snapshot(of: toast), as: .scaledImage)
    }
}

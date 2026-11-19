import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-207: a chat-list row in the Snoozed filter shows when its snooze
/// ends in place of the preview.
@MainActor
struct InboxSnoozeSnapshotTests {
    private func row(_ model: ChatListRowModel) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                ChatListRow(model: model, imageLoader: nil)
                    .frame(width: 320)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func snoozedRow() {
        var model = ChatListRowModel(
            id: "!snoozed",
            title: "Alice",
            isDirect: true,
            preview: "See you at the station at six",
            timestamp: "3:42 PM"
        )
        model.inboxNote = "Snoozed until tomorrow 9:00 AM"
        assertSnapshot(of: row(model), as: .scaledImage)
    }
}

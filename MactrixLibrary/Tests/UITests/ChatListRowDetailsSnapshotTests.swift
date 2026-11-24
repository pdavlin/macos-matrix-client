import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-224: a chat-list row with a saved draft ("Draft:" and the text)
/// and a row where someone types, in light and dark.
@MainActor
struct ChatListRowDetailsSnapshotTests {
    private func row(_ model: ChatListRowModel, appearance: NSAppearance.Name) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                ChatListRow(model: model, imageLoader: nil)
                    .frame(width: 320)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance, so the snapshot does not follow the system's.
        controller.view.appearance = NSAppearance(named: appearance)
        return controller
    }

    private var draftRow: ChatListRowModel {
        var model = ChatListRowModel(
            id: "!draft",
            title: "Release planning",
            preview: "Alex: Shipping Thursday",
            timestamp: "3:42 PM"
        )
        model.draft = "Can we move the review to Friday morning instead?"
        return model
    }

    private var typingRow: ChatListRowModel {
        var model = ChatListRowModel(
            id: "!typing",
            title: "Release planning",
            preview: "Alex: Shipping Thursday",
            timestamp: "3:42 PM",
            unread: ChatListUnread(count: 2, isUnread: true)
        )
        model.typingNames = ["Alex", "Sam"]
        return model
    }

    private var directTypingRow: ChatListRowModel {
        var model = ChatListRowModel(
            id: "!dm",
            title: "Alex Kim",
            isDirect: true,
            preview: "See you at six",
            timestamp: "Tue"
        )
        model.typingNames = ["Alex Kim"]
        return model
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func draftLight() {
        assertSnapshot(of: row(draftRow, appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func draftDark() {
        assertSnapshot(of: row(draftRow, appearance: .darkAqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func typingLight() {
        assertSnapshot(of: row(typingRow, appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func typingDark() {
        assertSnapshot(of: row(typingRow, appearance: .darkAqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func directTypingLight() {
        assertSnapshot(of: row(directTypingRow, appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func directTypingDark() {
        assertSnapshot(of: row(directTypingRow, appearance: .darkAqua), as: .scaledImage)
    }
}

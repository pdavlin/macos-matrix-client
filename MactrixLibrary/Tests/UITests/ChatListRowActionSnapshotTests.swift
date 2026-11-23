import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-222: the Archive button a chat-list row shows under the pointer.
///
/// The snapshots draw the button without a pointer
/// (`showsActionWithoutHover`). The button's own hover color needs a
/// pointer and is not shown.
@MainActor
struct ChatListRowActionSnapshotTests {
    private static let archive = ChatListRowAction(title: "Archive", systemImage: "archivebox") {}
    private static let unarchive = ChatListRowAction(title: "Unarchive", systemImage: "tray.and.arrow.up") {}

    private static let readModel = ChatListRowModel(
        id: "!read",
        title: "Release planning",
        preview: "Alice: Shipping Thursday, unless the notarization queue backs up again",
        timestamp: "Tue"
    )

    private static let unreadModel = ChatListRowModel(
        id: "!unread",
        title: "Alice",
        isDirect: true,
        preview: "See you at the station at six",
        timestamp: "3:42 PM",
        unread: ChatListUnread(count: 4, isUnread: true),
        network: .whatsApp
    )

    private func hosting(_ row: ChatListRow, appearance: NSAppearance.Name = .aqua) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                row
                    .frame(width: 320)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance: an unpinned snapshot flips with light/dark mode.
        controller.view.appearance = NSAppearance(named: appearance)
        return controller
    }

    private func row(_ model: ChatListRowModel, action: ChatListRowAction?, shown: Bool) -> ChatListRow {
        ChatListRow(model: model, imageLoader: nil, primaryAction: action, showsActionWithoutHover: shown)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func readRowWithArchiveButton() {
        assertSnapshot(of: hosting(row(Self.readModel, action: Self.archive, shown: true)), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func unreadRowWithArchiveButtonDark() {
        assertSnapshot(
            of: hosting(row(Self.unreadModel, action: Self.archive, shown: true), appearance: .darkAqua),
            as: .scaledImage
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func archivedRowWithUnarchiveButton() {
        assertSnapshot(of: hosting(row(Self.readModel, action: Self.unarchive, shown: true)), as: .scaledImage)
    }

    /// The button floats over the row: the row is as tall with it as
    /// without it, and as tall as a row with no action.
    @Test
    func buttonKeepsTheRowHeight() {
        for model in [Self.readModel, Self.unreadModel] {
            let plain = hosting(ChatListRow(model: model, imageLoader: nil)).view.fittingSize
            let hidden = hosting(row(model, action: Self.archive, shown: false)).view.fittingSize
            let shown = hosting(row(model, action: Self.archive, shown: true)).view.fittingSize
            #expect(hidden.height == plain.height)
            #expect(shown.height == plain.height)
            #expect(shown.width == plain.width)
        }
    }
}

import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-77: the label rail, the Create/Edit Label sheet, and the icon and
/// color picker.
///
/// No image loader, so every avatar is the placeholder. References render at
/// a fixed 2x through `.scaledImage` with the light appearance pinned; font
/// rasterization still varies by OS build, so snapshots are the local and
/// agent-side gate (contract R-8).
@MainActor
struct LabelSnapshotTests {
    private func snapshot(of view: some View, width: CGFloat, height: CGFloat? = nil) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: width, height: height)
                    .background(Color(NSColor.windowBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    private let labels = [
        ChatLabel(id: "work", name: "Work", colorIndex: 6, icon: "briefcase", rooms: ["!a", "!b"]),
        ChatLabel(id: "family", name: "Family", colorIndex: 0, isMuted: true, rooms: ["!c"]),
        ChatLabel(id: "games", name: "Games", colorIndex: 3, icon: "gamecontroller", rooms: ["!d"]),
        ChatLabel(id: "misc", name: "misc", rooms: ["!e"]),
    ]

    private let badges: [String: ChatLabelBadge] = ["work": .count(3), "family": .dot, "games": .dot]

    private let chats = [
        ChatListRowModel(id: "!a", title: "Release planning"),
        ChatListRowModel(id: "!b", title: "Alice", isDirect: true),
        ChatListRowModel(id: "!c", title: "Homelab"),
        ChatListRowModel(id: "!d", title: "Bob", isDirect: true, network: .signal),
        ChatListRowModel(id: "!e", title: "Weekend climbing"),
    ]

    // MARK: Rail

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func railInboxSelected() {
        let rail = LabelRail(labels: labels, badges: badges, selection: nil, actions: .none)
        assertSnapshot(of: snapshot(of: rail, width: 68, height: 360), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func railLabelSelected() {
        let rail = LabelRail(labels: labels, badges: badges, selection: "games", actions: .none)
        assertSnapshot(of: snapshot(of: rail, width: 68, height: 360), as: .scaledImage)
    }

    // MARK: Sheet

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func editSheetNew() {
        let sheet = LabelEditSheet(
            isNew: true,
            draft: ChatLabelDraft(),
            chats: chats,
            imageLoader: nil,
            onCancel: {},
            onSave: { _ in }
        )
        assertSnapshot(of: snapshot(of: sheet, width: 440), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func editSheetEditing() {
        let sheet = LabelEditSheet(
            isNew: false,
            draft: ChatLabelDraft(label: labels[0]),
            chats: chats,
            imageLoader: nil,
            onCancel: {},
            onSave: { _ in }
        )
        assertSnapshot(of: snapshot(of: sheet, width: 440), as: .scaledImage)
    }

    // MARK: Picker

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func pickerContent() {
        let picker = LabelIconColorPickerContent(name: "Work", colorIndex: .constant(6), icon: .constant("briefcase"))
        assertSnapshot(of: snapshot(of: picker.fixedSize(), width: 300), as: .scaledImage)
    }
}

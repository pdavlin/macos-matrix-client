import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-141 Phase B: the merged chat's detail placeholder, the room
/// inspector's merged-chat section, and the Merge Chats sheet's inline error.
///
/// No image loader, so every avatar is the placeholder. References render at
/// a fixed 2x through `.scaledImage` with the light appearance pinned; font
/// rasterization still varies by OS build, so snapshots are the local and
/// agent-side gate (contract R-8). The sheet shows an AppKit text field, so
/// its test uses `assertTextFieldSnapshot` (MATRIX-120).
@MainActor
struct MergedChatWiringSnapshotTests {
    private func snapshot(of view: some View, width: CGFloat, height: CGFloat? = nil) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: width, height: height)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    private static let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2", "!s3"])

    private static let members = [
        ChatListRowModel(id: "!s1", title: "Seth Redacted", isDirect: true, network: .slack),
        ChatListRowModel(id: "!s2", title: "Seth Redacted", isDirect: true, network: .slack),
        ChatListRowModel(id: "!s3", title: "Seth R.", isDirect: true, network: .googleChat),
    ]

    // MARK: Detail placeholder

    /// Three members over two networks: two badges on the heading avatar,
    /// one badge per member, and "(2)" on the second Slack chat's label.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func detailPlaceholder() throws {
        let merged = try #require(ChatListMerging.entry(for: Self.seth, members: Self.members.map { ChatListEntry(row: $0) }))
        let placeholder = MergedChatDetailPlaceholder(mergedRow: merged.row, members: Self.members, imageLoader: nil)
        assertSnapshot(of: snapshot(of: placeholder, width: 520, height: 420), as: .scaledImage)
    }

    // MARK: Inspector section

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func inspectorSectionMergeable() {
        let section = MergedChatInspectorSection(status: .mergeable, isEditable: true, onMerge: {}, onEdit: {}, onUnmerge: {})
        assertSnapshot(of: snapshot(of: section.padding(12), width: 260), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func inspectorSectionMember() {
        let section = MergedChatInspectorSection(
            status: .member(of: Self.seth),
            isEditable: true,
            onMerge: {},
            onEdit: {},
            onUnmerge: {}
        )
        assertSnapshot(of: snapshot(of: section.padding(12), width: 260), as: .scaledImage)
    }

    // MARK: Merged chat inspector (MATRIX-149)

    /// The merged chat's own inspector: its name, each member chat with the
    /// line that tells it apart, and "Edit Merged Chat…". The third member
    /// has no detail entry, so it shows its network.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func mergedChatInspector() throws {
        let merged = try #require(ChatListMerging.entry(for: Self.seth, members: Self.members.map { ChatListEntry(row: $0) }))
        let inspector = MergedChatInspectorView(
            mergedRow: merged.row,
            members: Self.members,
            memberDetails: ["!s1": "Slack • DevObsessed", "!s2": "Slack • Acme"],
            imageLoader: nil,
            isEditable: true,
            onEdit: {}
        )
        assertSnapshot(of: snapshot(of: inspector, width: 260, height: 400), as: .scaledImage)
    }

    // MARK: Sheet error

    /// A refused write: the inline error sits above the buttons.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func sheetSaveError() {
        let sheet = MergeChatsSheet(
            mode: .edit,
            draft: .constant(MergedChatDraft(merge: Self.seth)),
            chats: Self.members,
            imageLoader: nil,
            onAddChat: {},
            onCancel: {},
            onSubmit: { _ in },
            errorMessage: "The merged chat could not be saved. Check the connection and try again."
        )
        assertTextFieldSnapshot(of: snapshot(of: sheet, width: 420), as: .scaledImage)
    }
}

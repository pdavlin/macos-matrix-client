import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-141: the merged chat-list row and the Merge Chats sheet.
///
/// The merged rows come from `ChatListMerging`, so the references pin what
/// the sidebar will draw. No image loader, so every avatar is the
/// placeholder. References render at a fixed 2x through `.scaledImage` with
/// the light appearance pinned; font rasterization still varies by OS build,
/// so snapshots are the local and agent-side gate (contract R-8). The sheet
/// shows an AppKit text field, so its tests use `assertTextFieldSnapshot`
/// (MATRIX-120).
@MainActor
struct MergedChatSnapshotTests {
    private func snapshot(of view: some View, width: CGFloat) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: width)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    private static let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"])

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func member(
        _ id: String,
        minutesAgo: Double,
        preview: String,
        timestamp: String,
        unread: ChatListUnread = ChatListUnread(),
        network: ChatListNetwork? = .slack
    ) -> ChatListEntry {
        ChatListEntry(
            row: ChatListRowModel(
                id: id,
                title: "Seth Redacted",
                isDirect: true,
                preview: preview,
                timestamp: timestamp,
                unread: unread,
                network: network
            ),
            lastActivity: Self.now.addingTimeInterval(-minutesAgo * 60)
        )
    }

    private func mergedRow(_ entries: [ChatListEntry]) throws -> ChatListRowModel {
        let items = ChatListMerging.items(entries: entries, document: MergedChatDocument(merges: [Self.seth]))
        return try #require(items.first?.mergedChat?.row)
    }

    private func row(_ model: ChatListRowModel) -> NSHostingController<AnyView> {
        snapshot(of: ChatListRow(model: model, imageLoader: nil), width: 320)
    }

    // MARK: Rows

    /// Two Slack chats: one badge, summed count, the newest preview.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func mergedRowUnread() throws {
        let model = try mergedRow([
            member("!s2", minutesAgo: 2, preview: "Pizza at six?", timestamp: "3:42 PM",
                   unread: ChatListUnread(count: 2, isUnread: true)),
            member("!s1", minutesAgo: 40, preview: "Deploy is green", timestamp: "3:04 PM",
                   unread: ChatListUnread(count: 3, hasMention: true, isUnread: true)),
        ])
        assertSnapshot(of: row(model), as: .scaledImage)
    }

    /// Every member muted: the gray count and the bell.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func mergedRowMuted() throws {
        let model = try mergedRow([
            member("!s1", minutesAgo: 5, preview: "Deploy is green", timestamp: "3:39 PM",
                   unread: ChatListUnread(count: 1, isUnread: true, isMuted: true)),
            member("!s2", minutesAgo: 60, preview: "Pizza at six?", timestamp: "2:44 PM",
                   unread: ChatListUnread(count: 4, isUnread: true, isMuted: true)),
        ])
        assertSnapshot(of: row(model), as: .scaledImage)
    }

    /// Slack and Google Chat: two badges on the avatar.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func mergedRowTwoNetworks() throws {
        let model = try mergedRow([
            member("!s2", minutesAgo: 1, preview: "On my way", timestamp: "3:43 PM", network: .googleChat),
            member("!s1", minutesAgo: 30, preview: "Deploy is green", timestamp: "3:14 PM"),
        ])
        assertSnapshot(of: row(model), as: .scaledImage)
    }

    /// The pinned tile draws the same badge stack at its larger size.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func mergedPinnedTileThreeNetworks() {
        var model = ChatListRowModel(id: "m-seth", title: "Seth", isDirect: true, network: .slack)
        model.additionalNetworks = [.googleChat, .groupMe]
        let tile = PinnedChatTile(model: model, isSelected: false, imageLoader: nil, action: {})
        assertSnapshot(of: snapshot(of: tile, width: 96), as: .scaledImage)
    }

    // MARK: Sheet

    private static let sheetChats = [
        ChatListRowModel(id: "!s1", title: "Seth Redacted", isDirect: true, network: .slack),
        ChatListRowModel(id: "!s2", title: "Seth Redacted", isDirect: true, network: .slack),
        ChatListRowModel(id: "!s3", title: "Seth R.", isDirect: true, network: .googleChat),
    ]

    private func sheet(mode: MergeChatsSheet.Mode, draft: MergedChatDraft) -> NSHostingController<AnyView> {
        let sheet = MergeChatsSheet(
            mode: mode,
            draft: .constant(draft),
            chats: Self.sheetChats,
            imageLoader: nil,
            onAddChat: {},
            onCancel: {},
            onSubmit: { _ in }
        )
        return snapshot(of: sheet, width: 420)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func sheetCreate() {
        let draft = MergedChatDraft(chats: Array(Self.sheetChats.prefix(2)))
        assertTextFieldSnapshot(of: sheet(mode: .create, draft: draft), as: .scaledImage)
    }

    /// One chat left: Merge is disabled.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func sheetCreateOneChat() {
        let draft = MergedChatDraft(chats: [Self.sheetChats[0]])
        assertTextFieldSnapshot(of: sheet(mode: .create, draft: draft), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func sheetEdit() {
        let draft = MergedChatDraft(name: "Seth", rooms: ["!s1", "!s2", "!s3"], defaultRoom: "!s2", avatarRoom: "!s3")
        assertTextFieldSnapshot(of: sheet(mode: .edit, draft: draft), as: .scaledImage)
    }
}

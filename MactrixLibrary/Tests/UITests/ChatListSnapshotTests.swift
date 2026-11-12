import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-67: the inbox chat-list row and pinned favourite tile in each state
/// the sidebar can show.
///
/// No image loader, so every avatar is the placeholder: the references pin
/// layout and type, not remote images. Snapshot references render at a fixed
/// 2x through `.scaledImage`, so the attached display's backing scale does not
/// affect the result. Font rasterization still varies by OS build; snapshots
/// are the local/agent-side gate (contract R-8).
@MainActor
struct ChatListSnapshotTests {
    private func snapshot(of view: some View, width: CGFloat) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: width)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance: an unpinned snapshot flips with light/dark mode
        // and fails by time of day.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    private func row(_ model: ChatListRowModel) -> NSHostingController<AnyView> {
        snapshot(of: ChatListRow(model: model, imageLoader: nil), width: 320)
    }

    private func tile(_ model: ChatListRowModel, isSelected: Bool = false) -> NSHostingController<AnyView> {
        snapshot(of: PinnedChatTile(model: model, isSelected: isSelected, imageLoader: nil, action: {}), width: 96)
    }

    // MARK: Rows

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func readRow() {
        let model = ChatListRowModel(
            id: "!read",
            title: "Release planning",
            preview: "Alice: Shipping Thursday, unless the notarization queue backs up again",
            timestamp: "Tue"
        )
        assertSnapshot(of: row(model), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func unreadRowWithCount() {
        let model = ChatListRowModel(
            id: "!unread",
            title: "Alice",
            isDirect: true,
            preview: "See you at the station at six",
            timestamp: "3:42 PM",
            unread: ChatListUnread(count: 4, isUnread: true)
        )
        assertSnapshot(of: row(model), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func mentionRow() {
        let model = ChatListRowModel(
            id: "!mention",
            title: "Homelab",
            preview: "Bob: @Patrick can you look at the backup job?",
            timestamp: "9:05 AM",
            unread: ChatListUnread(count: 12, hasMention: true, isUnread: true)
        )
        assertSnapshot(of: row(model), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func mutedRowWithCount() {
        let model = ChatListRowModel(
            id: "!muted",
            title: "Neighbourhood",
            preview: "Carol: Bins go out tomorrow",
            timestamp: "Yesterday",
            unread: ChatListUnread(count: 128, isUnread: true, isMuted: true)
        )
        assertSnapshot(of: row(model), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func rowWithNetworkBadge() {
        let model = ChatListRowModel(
            id: "!bridged",
            title: "Dana",
            isDirect: true,
            preview: "Photo",
            timestamp: "10/15/26",
            network: .whatsApp
        )
        assertSnapshot(of: row(model), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func longTitleTruncates() {
        let model = ChatListRowModel(
            id: "!long",
            title: "A room with a name far too long to fit on one line of the sidebar",
            preview: "You: ok",
            timestamp: "Yesterday",
            unread: ChatListUnread(count: 1, isUnread: true)
        )
        assertSnapshot(of: row(model), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func sendFailureRow() {
        let model = ChatListRowModel(
            id: "!failed",
            title: "Erin",
            isDirect: true,
            preview: "You: Running ten minutes late",
            timestamp: "3:40 PM",
            hasSendFailure: true
        )
        assertSnapshot(of: row(model), as: .scaledImage)
    }

    /// MATRIX-123: the chat list at its narrowest. The sidebar column's
    /// minimum is 240 pt of chat list beside the label rail
    /// (`SidebarView.minimumWidth`), and the macOS sidebar `List` insets each
    /// row 16 pt on each side, so a row gets 208 pt. The names must keep most
    /// of that width; the times stay whole.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func minimumWidthLongNames() {
        let minimumChatListWidth: CGFloat = 240
        let sidebarListRowInset: CGFloat = 16
        let models: [ChatListRowModel] = [
            ChatListRowModel(
                id: "!games",
                title: "#omaha-board-games",
                preview: "Jo: Catan on Friday? I can bring the expansion",
                timestamp: "9:23 AM",
                unread: ChatListUnread(count: 3, isUnread: true)
            ),
            ChatListRowModel(
                id: "!pets",
                title: "#pets_and_other_animals",
                preview: "Sam: Photo",
                timestamp: "Yesterday"
            ),
            ChatListRowModel(
                id: "!infra",
                title: "dt_core-infrastructure",
                preview: "Deploy finished",
                timestamp: "10/15/26",
                unread: ChatListUnread(count: 1, isUnread: true, isMuted: true)
            ),
            ChatListRowModel(
                id: "!dm",
                title: "Brian Ruch \u{2022} DevObs",
                isDirect: true,
                preview: "Brian: Can you look at the alert rules?",
                timestamp: "12:05 PM",
                network: .slack
            ),
        ]
        let list = VStack(spacing: 0) {
            ForEach(models) { model in
                ChatListRow(model: model, imageLoader: nil)
            }
        }
        .padding(.horizontal, sidebarListRowInset)
        assertSnapshot(of: snapshot(of: list, width: minimumChatListWidth), as: .scaledImage)
    }

    // MARK: Pinned tiles

    /// MATRIX-123: a direct chat's tile shows the first name only.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func pinnedTileDirectFirstName() {
        let model = ChatListRowModel(id: "!pinned-dm", title: "Seth Redacted", isDirect: true, network: .whatsApp)
        assertSnapshot(of: tile(model), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func pinnedTileUnread() {
        let model = ChatListRowModel(
            id: "!pinned-unread",
            title: "Alice",
            isDirect: true,
            unread: ChatListUnread(count: 3, isUnread: true),
            network: .signal
        )
        assertSnapshot(of: tile(model), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func pinnedTileRead() {
        assertSnapshot(of: tile(ChatListRowModel(id: "!pinned-read", title: "Family")), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func pinnedTileSelected() {
        assertSnapshot(
            of: tile(ChatListRowModel(id: "!pinned-selected", title: "Family"), isSelected: true),
            as: .scaledImage
        )
    }

    // MARK: Pinned grid

    /// MATRIX-150: the pinned grid above the chat list, as the sidebar draws
    /// it. The macOS sidebar `List` insets each row 16 pt on each side, the
    /// grid's row too, so the stack gets the same padding here.
    private func pinnedGridAboveRows(width: CGFloat) -> NSHostingController<AnyView> {
        let sidebarListRowInset: CGFloat = 16
        let pinned: [ChatListRowModel] = [
            ChatListRowModel(
                id: "!p1",
                title: "Alice Example",
                isDirect: true,
                unread: ChatListUnread(count: 3, isUnread: true),
                network: .signal
            ),
            ChatListRowModel(id: "!p2", title: "Family"),
            ChatListRowModel(id: "!p3", title: "Seth Redacted", isDirect: true, network: .whatsApp),
            ChatListRowModel(id: "!p4", title: "Release planning", unread: ChatListUnread(isUnread: true)),
            ChatListRowModel(id: "!p5", title: "Bo", isDirect: true),
        ]
        let rows: [ChatListRowModel] = [
            ChatListRowModel(
                id: "!r1",
                title: "Homelab",
                preview: "Bob: can you look at the backup job?",
                timestamp: "9:05 AM",
                unread: ChatListUnread(count: 2, isUnread: true)
            ),
            ChatListRowModel(id: "!r2", title: "Dana", isDirect: true, preview: "Photo", timestamp: "Tue", network: .slack),
            ChatListRowModel(id: "!r3", title: "Neighbourhood", preview: "Carol: Bins go out tomorrow", timestamp: "10/15/26"),
        ]
        let list = VStack(spacing: 0) {
            PinnedChatGrid(pinned) { model in
                PinnedChatTile(model: model, isSelected: model.id == "!p2", imageLoader: nil, action: {})
            }
            ForEach(rows) { model in
                ChatListRow(model: model, imageLoader: nil)
            }
        }
        .padding(.horizontal, sidebarListRowInset)
        return snapshot(of: list, width: width)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func pinnedGridAboveRowsWidth260() {
        assertSnapshot(of: pinnedGridAboveRows(width: 260), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func pinnedGridAboveRowsWidth340() {
        assertSnapshot(of: pinnedGridAboveRows(width: 340), as: .scaledImage)
    }
}

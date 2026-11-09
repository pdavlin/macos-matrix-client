import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-129: group bubble clusters, colored initials, and the dense row.
///
/// No image loader, so every face is its colored initials: the references
/// pin layout and color, not remote images. References render at a fixed 2x
/// through `.scaledImage`; snapshots are the local/agent-side gate (contract
/// R-8).
@MainActor
struct ChatListAvatarSnapshotTests {
    private let heroes: [ChatListHero] = [
        ChatListHero(userId: "@alice:example.org", displayName: "Alice Liddell", avatarUrl: "mxc://example.org/alice"),
        ChatListHero(userId: "@bob:example.org", displayName: "Bob Ross"),
        ChatListHero(userId: "@carol:example.org", displayName: "Carol"),
        ChatListHero(userId: "@dan:example.org", displayName: "Dan Brown"),
        ChatListHero(userId: "@erin:example.org", displayName: "Erin Hart"),
    ]

    private func snapshot(
        of view: some View,
        appearance: NSAppearance.Name = .aqua
    ) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance: an unpinned snapshot flips with light/dark mode.
        controller.view.appearance = NSAppearance(named: appearance)
        return controller
    }

    /// A group row model with the first `count` heroes and `members` other
    /// members.
    private func group(_ count: Int, members: Int, network: ChatListNetwork? = nil) -> ChatListRowModel {
        ChatListRowModel(
            id: "!group-\(count)-\(members):example.org",
            title: "Group of \(members)",
            preview: "Carol: Saturday works for me",
            timestamp: "9:41 AM",
            network: network,
            heroes: Array(heroes.prefix(count)),
            otherMemberCount: members
        )
    }

    /// Clusters of 2, 3, and 5 people, and an overflowing group, side by side
    /// at one avatar size.
    private func clusterStrip(size: CGFloat) -> some View {
        HStack(spacing: 12) {
            ForEach([group(2, members: 2), group(3, members: 3), group(5, members: 5), group(5, members: 23)]) { model in
                ChatListAvatar(model: model, size: size, imageLoader: nil)
            }
        }
    }

    // MARK: Clusters

    /// Compact mode: at most three bubbles and no "+N".
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func clusters36() {
        assertSnapshot(of: snapshot(of: clusterStrip(size: 36)), as: .scaledImage)
    }

    /// Full mode: up to five bubbles; the 23-member group shows four faces
    /// and "+19".
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func clusters44() {
        assertSnapshot(of: snapshot(of: clusterStrip(size: 44)), as: .scaledImage)
    }

    // MARK: Initials

    /// People take two initials colored by user ID; rooms take one, colored
    /// by room ID; a name with no letter falls back to the localpart, then
    /// "#".
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func coloredInitials() {
        let models: [ChatListRowModel] = [
            ChatListRowModel(id: "!dm1:example.org", title: "Bob Ross", isDirect: true, heroes: [heroes[1]]),
            ChatListRowModel(
                id: "!dm2:example.org",
                title: "@zed:example.org",
                isDirect: true,
                heroes: [ChatListHero(userId: "@zed:example.org")]
            ),
            ChatListRowModel(id: "!room1:example.org", title: "Book club"),
            ChatListRowModel(id: "!room2:example.org", title: "🎉"),
            ChatListRowModel(id: "!dm3:example.org", title: "Seth Redacted", isDirect: true, network: .whatsApp),
        ]
        let strip = HStack(spacing: 12) {
            ForEach(models) { model in
                ChatListAvatar(model: model, size: 36, imageLoader: nil)
            }
        }
        assertSnapshot(of: snapshot(of: strip), as: .scaledImage)
    }

    /// Every palette slot as a grid of two rows of eight.
    private var paletteGrid: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(0 ..< 2, id: \.self) { (row: Int) in
                GridRow {
                    ForEach(0 ..< 8, id: \.self) { (column: Int) in
                        ChatListAvatarPlaceholder(
                            initials: ChatListInitials(text: "AB", paletteIndex: row * 8 + column),
                            size: 36
                        )
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    }
                }
            }
        }
    }

    /// Every palette slot on a light sidebar, so a palette change shows in
    /// review.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func initialsPaletteLight() {
        assertSnapshot(of: snapshot(of: paletteGrid), as: .scaledImage)
    }

    /// Every palette slot on a dark sidebar: the white initials must read on
    /// both.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func initialsPaletteDark() {
        assertSnapshot(of: snapshot(of: paletteGrid, appearance: .darkAqua), as: .scaledImage)
    }

    // MARK: Rows and tiles

    /// The dense row with a three-bubble cluster and a network badge.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func denseGroupRow() {
        let model = group(5, members: 23, network: .signal)
        assertSnapshot(of: snapshot(of: ChatListRow(model: model, imageLoader: nil).frame(width: 304)), as: .scaledImage)
    }

    /// A pinned group: five-bubble mode with the "+N" label.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func pinnedGroupTile() {
        let model = group(5, members: 23)
        let tile = PinnedChatTile(model: model, isSelected: false, imageLoader: nil, action: {})
            .frame(width: 96)
        assertSnapshot(of: snapshot(of: tile), as: .scaledImage)
    }
}

import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-167: the sidebar rail with spaces. The loader holds one
/// solid-color icon per URL in its cache, so the space icons draw without a
/// network. Local gate only, as the other snapshots (contract R-8).
@MainActor
struct SpaceRailSnapshotTests {
    /// Serves a solid-color square for each known URL, from the cache.
    private struct IconLoader: ImageLoader {
        let colors: [String: NSColor]

        func cachedImage(matrixUrl: String) -> Image? {
            guard let color = colors[matrixUrl] else { return nil }
            let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
                color.setFill()
                rect.fill()
                return true
            }
            return Image(nsImage: image)
        }

        func loadImage(matrixUrl: String, size _: CGSize?) async throws -> Image? {
            cachedImage(matrixUrl: matrixUrl)
        }
    }

    private static let loader = IconLoader(colors: ["mxc://a/dev": .systemTeal])

    /// One space with an icon and one without.
    private func spaces(devBadge: ChatLabelBadge = .none, pizzaBadge: ChatLabelBadge = .none) -> [ChatListRailSpace] {
        [
            ChatListRailSpace(id: "!dev", name: "DevObsessed", avatarUrl: "mxc://a/dev", badge: devBadge),
            ChatListRailSpace(id: "!pizza", name: "pizza box audit committee", badge: pizzaBadge),
        ]
    }

    private let labels = [
        ChatLabel(id: "work", name: "Work", colorIndex: 6, icon: "briefcase", rooms: ["!a", "!b"]),
        ChatLabel(id: "family", name: "Family", colorIndex: 0, isMuted: true, rooms: ["!c"]),
    ]

    private func rail(
        spaces: [ChatListRailSpace],
        labels: [ChatLabel],
        selection: ChatListRailFilter
    ) -> NSHostingController<AnyView> {
        let view = LabelRail(
            spaces: spaces,
            labels: labels,
            badges: ["work": .count(3)],
            selection: selection,
            imageLoader: Self.loader,
            actions: .none
        )
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: 68, height: 360)
                    .background(Color(NSColor.windowBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func railInboxOnly() {
        assertTextFieldSnapshot(of: rail(spaces: [], labels: [], selection: .inbox), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func railTwoSpaces() {
        assertTextFieldSnapshot(of: rail(spaces: spaces(), labels: [], selection: .inbox), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func railTwoSpacesTwoLabels() {
        assertTextFieldSnapshot(of: rail(spaces: spaces(), labels: labels, selection: .inbox), as: .scaledImage)
    }

    /// MATRIX-170: the rail's items from the launch cache alone, before a
    /// live space, a live room, or a live parent answer. The restored space
    /// selection applies too.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func railSpacesFromLaunchCache() {
        let dev = KnownSpace(id: "!dev", name: "DevObsessed", avatarUrl: "mxc://a/dev")
        let pizza = KnownSpace(id: "!pizza", name: "pizza box audit committee")
        let graph = SpaceGraph(cache: SpaceLaunchCache(
            topLevel: [dev, pizza],
            rooms: ["!d1": .init(parents: [dev]), "!p1": .init(parents: [pizza])]
        ))
        let items = ChatListRailSpace.items(
            joined: graph.topLevel.map { ChatListRailSpace(id: $0.id, name: $0.name, avatarUrl: $0.avatarUrl) },
            spaces: RoomSpaceMap(parents: graph.parents.mapValues { $0.map(\.id) }),
            chatIds: graph.launchChatIds,
            unread: [:]
        )
        let selection = ChatListRailFilter.space("!dev").resolved(
            labels: ChatLabelDocument(),
            spaceIds: Set(items.map(\.id))
        )
        assertTextFieldSnapshot(of: rail(spaces: items, labels: [], selection: selection), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func railSpaceSelectedWithUnreadMarks() {
        let marked = spaces(devBadge: .count(2), pizzaBadge: .dot)
        assertTextFieldSnapshot(of: rail(spaces: marked, labels: labels, selection: .space("!pizza")), as: .scaledImage)
    }
}

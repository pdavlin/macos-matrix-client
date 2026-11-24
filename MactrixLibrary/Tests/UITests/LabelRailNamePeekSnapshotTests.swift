import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
import Tokens
@testable import UI

/// MATRIX-227: the rail name peek next to the rail item a Go-menu key
/// selected, over the edge of the chat list. The snapshots show the peek at
/// rest, in light and dark, for a label and for a long space name that
/// truncates; motion is not captured. Local gate only, as the other
/// snapshots (contract R-8).
@MainActor
struct LabelRailNamePeekSnapshotTests {
    private static let loader = StubImageLoader(colors: ["mxc://a/dev": .stubTeal])

    private let spaces = [
        ChatListRailSpace(id: "!dev", name: "DevObsessed", avatarUrl: "mxc://a/dev"),
        ChatListRailSpace(id: "!long", name: "The very long name of a pizza box audit committee space"),
    ]

    private let labels = [
        ChatLabel(id: "work", name: "Work", colorIndex: 6, icon: "briefcase", rooms: ["!a"]),
        ChatLabel(id: "family", name: "Family", colorIndex: 0, rooms: ["!c"]),
    ]

    private func sidebar(peeking filter: ChatListRailFilter, appearance: NSAppearance.Name) -> NSHostingController<AnyView> {
        var peek = RailNamePeek()
        peek.show(filter, at: .now)
        let view = HStack(spacing: 0) {
            LabelRail(
                spaces: spaces,
                labels: labels,
                selection: filter,
                imageLoader: Self.loader,
                actions: .none
            )
            Divider()
            // Stands in for the chat list.
            Color(NSColor.controlBackgroundColor)
                .frame(width: 220)
        }
        .frame(height: 340)
        .labelRailNamePeek(peek.item) {}
        let controller = NSHostingController(
            rootView: AnyView(view.background(Color(NSColor.windowBackgroundColor)))
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance, so the snapshot does not follow the system's.
        controller.view.appearance = NSAppearance(named: appearance)
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func labelPeekLight() {
        assertTextFieldSnapshot(of: sidebar(peeking: .label("work"), appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func labelPeekDark() {
        assertTextFieldSnapshot(of: sidebar(peeking: .label("work"), appearance: .darkAqua), as: .scaledImage)
    }

    /// A long name truncates at the capsule's maximum width.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func longSpaceNamePeekLight() {
        assertTextFieldSnapshot(of: sidebar(peeking: .space("!long"), appearance: .aqua), as: .scaledImage)
    }

    /// The overlay draws nothing without a peek.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func noPeekLight() {
        let view = HStack(spacing: 0) {
            LabelRail(spaces: spaces, labels: labels, selection: .inbox, imageLoader: Self.loader, actions: .none)
            Divider()
            Color(NSColor.controlBackgroundColor)
                .frame(width: 220)
        }
        .frame(height: 340)
        .labelRailNamePeek(nil) {}
        let controller = NSHostingController(rootView: AnyView(view.background(Color(NSColor.windowBackgroundColor))))
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        assertTextFieldSnapshot(of: controller, as: .scaledImage)
    }
}

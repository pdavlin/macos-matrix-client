import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-226: the active filter chip of the sidebar header, for a list
/// filter, a label with a list filter, and a space, in light and dark.
///
/// `NSView.cacheDisplay` draws nothing for tinted glass (MATRIX-195), so the
/// glass snapshots draw the glass untinted and guard the layout: the
/// symbol, the name, the clear mark, the capsule. The opaque Reduce
/// Transparency snapshots show the tint colors. The tinted glass needs a
/// look in the app (contract R-8). Local gate only, as the other snapshots.
@MainActor
struct ChatListFilterChipSnapshotTests {
    private static let listFilter = ChatListActiveFilter(title: "Unread", systemImage: "circlebadge", tint: .accent)
    private static let label = ChatListActiveFilter(title: "Work · Unread", systemImage: "briefcase", tint: .palette(6))
    private static let space = ChatListActiveFilter(title: "DevObsessed", systemImage: "square.grid.2x2", tint: .palette(3))

    private func host(_ view: some View, appearance: NSAppearance.Name) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .padding(10)
                    .frame(width: 260, alignment: .leading)
                    .background(Color(NSColor.windowBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance, so the snapshot does not follow the system's.
        controller.view.appearance = NSAppearance(named: appearance)
        return controller
    }

    private func glass(_ filter: ChatListActiveFilter) -> some View {
        ChatListFilterChip(filter: filter, usesGlass: true, clear: {}).untintedForSnapshot()
    }

    private func opaque(_ filter: ChatListActiveFilter) -> some View {
        ChatListFilterChip(filter: filter, usesGlass: false, clear: {})
    }

    // MARK: Glass (untinted)

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func listFilterLight() {
        assertSnapshot(of: host(glass(Self.listFilter), appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func listFilterDark() {
        assertSnapshot(of: host(glass(Self.listFilter), appearance: .darkAqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func labelLight() {
        assertSnapshot(of: host(glass(Self.label), appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func labelDark() {
        assertSnapshot(of: host(glass(Self.label), appearance: .darkAqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func spaceLight() {
        assertSnapshot(of: host(glass(Self.space), appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func spaceDark() {
        assertSnapshot(of: host(glass(Self.space), appearance: .darkAqua), as: .scaledImage)
    }

    // MARK: Reduce Transparency (opaque, tinted)

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func opaqueListFilterLight() {
        assertSnapshot(of: host(opaque(Self.listFilter), appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func opaqueListFilterDark() {
        assertSnapshot(of: host(opaque(Self.listFilter), appearance: .darkAqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func opaqueLabelLight() {
        assertSnapshot(of: host(opaque(Self.label), appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func opaqueLabelDark() {
        assertSnapshot(of: host(opaque(Self.label), appearance: .darkAqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func opaqueSpaceLight() {
        assertSnapshot(of: host(opaque(Self.space), appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func opaqueSpaceDark() {
        assertSnapshot(of: host(opaque(Self.space), appearance: .darkAqua), as: .scaledImage)
    }
}

import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
import Tokens
@testable import UI

/// Snapshots of the merged chat's target picker chip (MATRIX-143, M2.5-4).
///
/// They pin the chip's fixed height, the "To:" line with the network badge,
/// the reason hint, and the truncation of a long name, in light and dark.
@MainActor
struct ComposerTargetPickerSnapshotTests {
    private static let options = [
        ComposerTargetOption(id: "!a:davlin.io", name: "DevObsessed", network: .slack),
        ComposerTargetOption(id: "!b:davlin.io", name: "pizza box audit committee", network: .slack),
        ComposerTargetOption(id: "!c:davlin.io", name: "Seth Example"),
    ]

    private func host(_ view: some View, appearance: NSAppearance.Name) -> NSViewController {
        let controller = NSHostingController(
            rootView: view
                .padding(8)
                .frame(width: 420, alignment: .leading)
                .background(Color(NSColor.windowBackgroundColor))
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance, so the snapshot does not flip with dark mode.
        controller.view.appearance = NSAppearance(named: appearance)
        return controller
    }

    private func picker(_ roomId: String, _ reason: MergedSendTarget.Reason) -> some View {
        ComposerTargetPicker(options: Self.options, selectedRoomId: roomId, reason: reason, onSelect: { _ in })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func chosenLight() {
        assertSnapshot(of: host(picker("!b:davlin.io", .chosen), appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func chosenDark() {
        assertSnapshot(of: host(picker("!b:davlin.io", .chosen), appearance: .darkAqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func defaultLight() {
        assertSnapshot(of: host(picker("!a:davlin.io", .defaultRoom), appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func defaultDark() {
        assertSnapshot(of: host(picker("!a:davlin.io", .defaultRoom), appearance: .darkAqua), as: .scaledImage)
    }

    /// A room with no detected network: no badge, the name alone.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func lastActiveWithoutNetwork() {
        assertSnapshot(of: host(picker("!c:davlin.io", .recentActivity), appearance: .aqua), as: .scaledImage)
    }

    /// A reply locks the chip: no chevron.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func replyLocked() {
        assertSnapshot(of: host(picker("!a:davlin.io", .reply), appearance: .aqua), as: .scaledImage)
    }

    /// The chip keeps its height for every reason and target.
    @Test(arguments: MergedSendTarget.Reason.allCases)
    func chipHeightIsFixed(reason: MergedSendTarget.Reason) {
        for option in Self.options {
            let controller = NSHostingController(
                rootView: ComposerTargetPicker(
                    options: Self.options,
                    selectedRoomId: option.id,
                    reason: reason,
                    onSelect: { _ in }
                )
            )
            #expect(controller.view.fittingSize.height == ComposerTargetToken.chipHeight)
        }
    }
}

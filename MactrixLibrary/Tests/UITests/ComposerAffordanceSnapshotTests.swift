import AppKit
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshot references are rendered at a fixed 2x through `.scaledImage`, so the backing
/// scale of whatever display is attached does not affect the result — see
/// `ScaledImageSnapshotting`. Font rasterization still varies by OS build, so CI runners on a
/// different macOS build can still differ. Snapshots stay the local/agent-side gate
/// (contract R-8); CI enforces the compile and logic suites.
@MainActor
struct ComposerAffordanceSnapshotTests {
    private func assertPinnedSnapshot(
        of view: some View,
        testName: String = #function
    ) {
        let controller = NSHostingController(rootView: view.padding())
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance: NSHostingController renders in the current system appearance,
        // so an unpinned snapshot flips with light/dark mode and fails by time of day.
        controller.view.appearance = NSAppearance(named: .aqua)

        assertSnapshot(of: controller, as: .scaledImage, testName: testName)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func scrollChipWithoutCount() {
        assertPinnedSnapshot(of: ScrollToBottomChip(unseenCount: 0) {})
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func scrollChipWithCount() {
        assertPinnedSnapshot(of: ScrollToBottomChip(unseenCount: 7) {})
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func scrollChipWithOverflowCount() {
        assertPinnedSnapshot(of: ScrollToBottomChip(unseenCount: 250) {})
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func sendFailure() {
        assertPinnedSnapshot(
            of: MessageSendFailureView(
                message: "the server rejected the message",
                retry: {},
                discard: {}
            )
            .frame(width: 420, alignment: .leading)
        )
    }
}

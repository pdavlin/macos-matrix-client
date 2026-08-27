import AppKit
import Models
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
struct RoomEncryptionBadgeSnapshotTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func encryptedBadge() {
        let controller = NSHostingController(
            rootView: RoomEncryptionBadge(state: .encrypted).padding()
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance: NSHostingController renders in the current system appearance,
        // so an unpinned snapshot flips with light/dark mode and fails by time of day.
        controller.view.appearance = NSAppearance(named: .aqua)

        assertSnapshot(of: controller, as: .scaledImage)
    }
}

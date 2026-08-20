import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshot references are recorded on the primary dev machine (macOS 27 beta, 2x scale).
/// CI runners image on a different OS build with different font rasterization and backing
/// scale, so pixel comparison there fails by environment, not by regression. Snapshots are
/// the local/agent-side gate (contract R-8); CI enforces the compile and logic suites.
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

        assertSnapshot(of: controller, as: .image)
    }
}

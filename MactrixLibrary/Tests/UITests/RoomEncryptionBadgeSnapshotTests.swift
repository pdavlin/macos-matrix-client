import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing

@testable import UI

@MainActor
struct RoomEncryptionBadgeSnapshotTests {
    @Test func encryptedBadge() {
        let controller = NSHostingController(
            rootView: RoomEncryptionBadge(state: .encrypted).padding()
        )
        controller.view.frame.size = controller.view.fittingSize

        assertSnapshot(of: controller, as: .image)
    }
}

import AppKit
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshot references render at a fixed 2x through `.scaledImage` — see
/// `ScaledImageSnapshotting`. Icons are SF symbols, not `NSWorkspace` file
/// icons, so the references do not depend on the installed app set.
@MainActor
struct AttachmentRowSnapshotTests {
    private func host(_ view: some View) -> NSHostingController<some View> {
        let controller = NSHostingController(rootView: view.padding())
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance: NSHostingController renders in the current system
        // appearance, so an unpinned snapshot flips with light/dark mode.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func fileRowWithSize() {
        let controller = host(
            AttachmentRowView(
                icon: Image(systemName: "doc"),
                title: "quarterly-report.pdf",
                subtitle: "1.2 MB"
            )
        )

        assertSnapshot(of: controller, as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func audioRowWithDurationAndError() {
        let controller = host(
            VStack(alignment: .leading) {
                AttachmentRowView(
                    icon: Image(systemName: "waveform"),
                    title: "Voice message.ogg",
                    subtitle: "0:42 · 128 KB"
                )
                MediaErrorLabel(message: "Failed to download")
            }
        )

        assertSnapshot(of: controller, as: .scaledImage)
    }
}

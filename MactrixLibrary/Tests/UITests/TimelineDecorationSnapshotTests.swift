import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// S-34: the container-owned decoration rows and the read-marker divider.
///
/// Snapshot references are rendered at a fixed 2x through `.scaledImage`, so
/// the backing scale of whatever display is attached does not affect the
/// result — see `ScaledImageSnapshotting`. Font rasterization still varies by
/// OS build, so CI runners on a different macOS build can still differ.
/// Snapshots stay the local/agent-side gate (contract R-8); CI enforces the
/// compile and logic suites.
@MainActor
struct TimelineDecorationSnapshotTests {
    private func snapshot(of view: some View, width: CGFloat = 420) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: width)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance: NSHostingController renders in the current system
        // appearance, so an unpinned snapshot flips with light/dark mode and
        // fails by time of day.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func typingIndicatorSingleUser() {
        assertSnapshot(of: snapshot(of: TypingIndicatorRow(names: ["Ada Lovelace"])), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func typingIndicatorMultipleUsers() {
        assertSnapshot(
            of: snapshot(of: TypingIndicatorRow(names: ["Ada Lovelace", "Grace Hopper"])),
            as: .scaledImage
        )
    }

    /// The pagination row's spinner animates on its own timer, so the capture
    /// uses the static substitute to land on one stable frame.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func paginationActivityRow() {
        assertSnapshot(
            of: snapshot(of: PaginationActivityRow().environment(\.usesStaticProgressIndicators, true)),
            as: .scaledImage
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func readMarkerRow() {
        assertSnapshot(of: snapshot(of: VirtualItemView(item: .readMarker)), as: .scaledImage)
    }
}

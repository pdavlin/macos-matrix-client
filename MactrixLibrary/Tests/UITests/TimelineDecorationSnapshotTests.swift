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
    private func snapshot(
        of view: some View,
        width: CGFloat? = 420,
        appearance: NSAppearance.Name = .aqua
    ) -> NSHostingController<AnyView> {
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
        controller.view.appearance = NSAppearance(named: appearance)
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

    /// S-35: the failure that replaces the activity row at the oldest end. It
    /// is static, so no progress-indicator substitution is needed.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func paginationFailureRow() {
        assertSnapshot(
            of: snapshot(of: PaginationFailureRow(message: "The Internet connection appears to be offline.") {}),
            as: .scaledImage
        )
    }

    /// MATRIX-136: the read marker as the "New" divider, after its glow
    /// has faded and before it dims. End states only: the glow is a moment.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func readMarkerRow() {
        assertSnapshot(of: snapshot(of: NewDividerRow(phase: .lit)), as: .scaledImage)
    }

    /// MATRIX-136: the "New" divider after the dim delay.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func readMarkerRowDimmed() {
        assertSnapshot(of: snapshot(of: NewDividerRow(phase: .dimmed)), as: .scaledImage)
    }

    /// 2024-03-14 12:00 UTC: far enough in the past to show the long date,
    /// and noon, so the date is the same in every time zone a test runs in.
    private static let pillDate = Date(timeIntervalSince1970: 1_710_417_600)

    /// MATRIX-136: the date divider as a day pill over a separator line.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func dateDividerRowLight() {
        assertSnapshot(
            of: snapshot(of: VirtualItemView(item: .dateDivider(date: Self.pillDate))),
            as: .scaledImage
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func dateDividerRowDark() {
        assertSnapshot(
            of: snapshot(of: VirtualItemView(item: .dateDivider(date: Self.pillDate)), appearance: .darkAqua),
            as: .scaledImage
        )
    }

    /// MATRIX-136: the floating sticky day pill, at its own size, as the
    /// timeline container hosts it.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func stickyDayPillLight() {
        assertSnapshot(of: snapshot(of: StickyDayPill(date: Self.pillDate), width: nil), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func stickyDayPillDark() {
        assertSnapshot(
            of: snapshot(of: StickyDayPill(date: Self.pillDate), width: nil, appearance: .darkAqua),
            as: .scaledImage
        )
    }
}

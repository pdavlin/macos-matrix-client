import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// S-35: the message-body states that are not a message — an undecryptable
/// event with the cause the SDK attributed, and the edit marker.
///
/// Snapshot references render at a fixed 2x through `.scaledImage`, so the
/// attached display's backing scale does not affect the result. Font
/// rasterization still varies by OS build; snapshots are the local/agent-side
/// gate (contract R-8).
@MainActor
struct MessageStateSnapshotTests {
    private func snapshot(of view: some View, width: CGFloat = 420) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: width, alignment: .leading)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance: an unpinned snapshot flips with light/dark mode
        // and fails by time of day.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    /// No attribution from the SDK: the row states the failure only.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func unableToDecryptWithoutCause() {
        assertSnapshot(of: snapshot(of: UnableToDecryptView(cause: .unknown)), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func unableToDecryptSentBeforeWeJoined() {
        assertSnapshot(of: snapshot(of: UnableToDecryptView(cause: .sentBeforeWeJoined)), as: .scaledImage)
    }

    /// The longest reason, to catch a cause text that clips instead of wrapping.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func unableToDecryptWithheldForUnverifiedDevice() {
        assertSnapshot(
            of: snapshot(of: UnableToDecryptView(cause: .withheldForUnverifiedOrInsecureDevice), width: 260),
            as: .scaledImage
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func editedMessageMarker() {
        assertSnapshot(
            of: snapshot(
                of: VStack(alignment: .leading, spacing: 2) {
                    Text("The meeting moved to Thursday.")
                    EditedMarker()
                }
            ),
            as: .scaledImage
        )
    }
}

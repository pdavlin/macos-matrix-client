import AppKit
import SwiftUI
import Testing
@testable import UI

/// Guards the property the snapshot references depend on: the render scale is an
/// input, not a consequence of the attached display.
///
/// Without this, a change that reverts to AppKit's
/// `bitmapImageRepForCachingDisplay(in:)` would pass every existing snapshot test
/// on the machine that recorded them and fail on every other machine.
@MainActor
struct ScaledImageSnapshottingTests {
    private func badgeView() -> NSView {
        let controller = NSHostingController(
            rootView: RoomEncryptionBadge(state: .encrypted).padding()
        )
        controller.view.frame.size = controller.view.fittingSize
        return controller.view
    }

    @Test(arguments: [1, 2, 3])
    func rendersAtTheRequestedScale(scale: Int) throws {
        let view = badgeView()
        let points = view.bounds.size

        let image = ScaledImageSnapshotting.render(view, scale: scale)
        let rep = try #require(image.representations.first as? NSBitmapImageRep)

        #expect(rep.pixelsWide == Int(points.width) * scale)
        #expect(rep.pixelsHigh == Int(points.height) * scale)
        // The NSImage keeps point dimensions; only the raster grows.
        #expect(image.size == points)
    }

    /// The committed references are recorded at this scale. Changing it
    /// invalidates every one of them at once, so it should never move silently.
    @Test
    func referenceScaleIsPinnedAtTwo() {
        #expect(ScaledImageSnapshotting.referenceScale == 2)
    }
}

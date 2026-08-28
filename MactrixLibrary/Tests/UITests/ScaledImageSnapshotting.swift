import AppKit
import SnapshotTesting

/// A snapshot strategy that renders at a scale the test chooses, not one the
/// hardware imposes.
///
/// The library's own `Snapshotting<NSView, NSImage>.image` renders through
/// `bitmapImageRepForCachingDisplay(in:)`. That AppKit call sizes its bitmap
/// from the view's backing scale, and a view with no window inherits the
/// backing scale of the main screen. So a reference recorded on a 2x display
/// and replayed on a 1x display differs in pixel data while reporting the same
/// point size — the failure reads as a layout regression when nothing about the
/// layout changed.
///
/// Building the `NSBitmapImageRep` by hand removes the screen from the path.
/// `pixelsWide` and `pixelsHigh` fix the raster dimensions; setting `size` back
/// to the point size tells AppKit the scale to draw at. `cacheDisplay(in:to:)`
/// then renders into that rep at exactly the requested resolution, whatever
/// display is attached.
enum ScaledImageSnapshotting {
    /// The scale every reference in this target is recorded at.
    ///
    /// The value is arbitrary but must not drift: changing it invalidates every
    /// committed reference at once. 2 matches a Retina display, so a failure
    /// diff opened by hand looks like what the eye expects.
    static let referenceScale = 2

    static func image(scale: Int = referenceScale) -> Snapshotting<NSView, NSImage> {
        SimplySnapshotting.image(precision: 1, perceptualPrecision: 1).pullback { view in
            // AppKit rendering is main-actor work, and the snapshot strategy's
            // closure is not isolated. Callers are `@MainActor` test methods
            // and `assertSnapshot` runs the pullback synchronously, so the
            // assertion holds; it traps loudly rather than racing if it ever
            // stops holding.
            MainActor.assumeIsolated {
                render(view, scale: scale)
            }
        }
    }

    /// Internal rather than private so `ScaledImageSnapshottingTests` can assert the
    /// raster dimensions directly — that assertion is the guard on this whole file.
    @MainActor
    static func render(_ view: NSView, scale: Int) -> NSImage {
        let bounds = view.bounds
        precondition(
            bounds.width > 0 && bounds.height > 0,
            "View is not renderable at size \(bounds.size)"
        )

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width) * scale,
            pixelsHigh: Int(bounds.height) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            preconditionFailure("Could not allocate a bitmap for \(bounds.size) at \(scale)x")
        }

        // Point size, not pixel size. The ratio between this and
        // pixelsWide/pixelsHigh is what makes the render happen at `scale`.
        rep.size = bounds.size

        view.cacheDisplay(in: bounds, to: rep)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

extension Snapshotting where Value == NSViewController, Format == NSImage {
    /// Renders a controller's view at the target's fixed reference scale.
    ///
    /// Use this rather than `.image` for any reference committed to the repo.
    /// `.image` is scale-dependent — see ``ScaledImageSnapshotting``.
    static var scaledImage: Snapshotting {
        ScaledImageSnapshotting.image().pullback { $0.view }
    }
}

import AppKit
import ObjectiveC
import Testing

/// Makes every screen report the reference scale for the life of the test
/// process (MATRIX-218).
///
/// The fault. A view with no window takes its backing scale from the main
/// screen. `ScaledImageSnapshotting` fixes the scale of the bitmap, but not
/// the scale that AppKit lays out and draws some controls at. A stepper-field
/// `DatePicker` puts its text half a point lower, and a small `ProgressView`
/// draws another spinner, when the main screen is 1x. The references were
/// recorded with a 2x main screen. With only a 1x external display attached,
/// the time sheet and the Threads pane snapshots failed, and nothing in the
/// code had changed.
///
/// The cure. The guard replaces `NSScreen.backingScaleFactor` with one that
/// returns `ScaledImageSnapshotting.referenceScale`. AppKit keeps the scale
/// it read first, so the guard must be in place before any test draws: a
/// suite that needs it takes the `.referenceScaleScreen` trait, which
/// installs it before the first test of the process starts. The replacement
/// stays for the rest of the process. The other snapshot tests give the same
/// render at 1x and 2x.
@MainActor
enum ReferenceScaleScreen {
    private static var isInstalled = false

    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        let selector = #selector(getter: NSScreen.backingScaleFactor)
        guard let method = class_getInstanceMethod(NSScreen.self, selector) else {
            Issue.record("MATRIX-218: NSScreen has no backingScaleFactor, so the guard is not installed")
            return
        }
        let replacement: @convention(block) (NSScreen) -> CGFloat = { _ in
            CGFloat(ScaledImageSnapshotting.referenceScale)
        }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
    }
}

/// Installs `ReferenceScaleScreen` when the testing library prepares the
/// suite. The library prepares every test after discovery and before any
/// test begins to run.
struct ReferenceScaleScreenTrait: SuiteTrait {
    func prepare(for _: Test) async throws {
        await ReferenceScaleScreen.install()
    }
}

extension Trait where Self == ReferenceScaleScreenTrait {
    /// The suite's snapshots need a 2x main screen. See `ReferenceScaleScreen`.
    static var referenceScaleScreen: Self {
        Self()
    }
}

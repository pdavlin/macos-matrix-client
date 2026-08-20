import SwiftUI

/// The seam every timeline candidate plugs into.
///
/// A candidate is a `View` that takes the harness and nothing else. It reads
/// `harness.store.items` for content and reports geometry back through `harness.probe`.
/// It must not own the drivers, the display link, or any data generation: keeping all of
/// that on the harness side is what makes S-13 and S-14 comparable.
///
/// ## What a candidate must implement
///
/// - An inverted, variable-height list over `harness.store.items` that starts at the
///   bottom (newest event visible).
/// - Day separators from `item.daySeparator` and sender headers from
///   `item.startsSenderRun`. Do not recompute grouping; the store already did it.
/// - `harness.probe.reportVisible(_:range:)` on every change of the on-screen set.
/// - `harness.probe.reportOffset(_:for:)` for the tracked item, in points from the top of
///   the viewport. See `AnchorProbe` for the exact contract.
/// - `harness.viewportDidScroll(distanceFromTop:)` on scroll, so automatic
///   back-pagination can arm.
///
/// ## What a candidate must not do
///
/// - Do not add throttling, coalescing, or debouncing to store reads. That is the thing
///   being measured.
/// - Do not change `HarnessConfiguration` from inside the view.
@MainActor
public protocol TimelineRenderer: View {
    /// Stable identifier written into the JSON report.
    ///
    /// The three descriptors are `nonisolated` so the renderer catalogue can be a plain
    /// static table. Conformers declare them as `nonisolated static let`.
    nonisolated static var rendererID: String { get }
    /// Name shown in the picker and the HUD.
    nonisolated static var displayName: String { get }
    /// One line on the approach, shown under the picker.
    nonisolated static var summary: String { get }

    init(harness: SpikeHarness)
}

/// A type-erased entry in the renderer picker.
///
/// The erasure sits at the root of the timeline, above the scroll view, and its type never
/// changes for a given selection, so it does not affect the identity or the diffing of the
/// content being measured.
public struct RendererDescriptor: Identifiable, Sendable, Hashable {
    public let id: String
    public let displayName: String
    public let summary: String
    private let build: @MainActor @Sendable (SpikeHarness) -> AnyView

    public init<Renderer: TimelineRenderer>(_ type: Renderer.Type) {
        self.id = Renderer.rendererID
        self.displayName = Renderer.displayName
        self.summary = Renderer.summary
        self.build = { harness in AnyView(Renderer(harness: harness)) }
    }

    @MainActor
    public func makeView(harness: SpikeHarness) -> AnyView {
        build(harness)
    }

    // Identity is the renderer id. The closure is not comparable and does not need to be.
    public static func == (lhs: RendererDescriptor, rhs: RendererDescriptor) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// A named coordinate space that SwiftUI candidates should attach to their scroll view, so
/// `reportOffset(_:for:)` measures against the viewport rather than the window.
public enum SpikeCoordinateSpace {
    public static let viewport = "timeline-spike-viewport"
}

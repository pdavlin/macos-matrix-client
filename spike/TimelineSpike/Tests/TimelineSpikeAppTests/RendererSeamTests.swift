import AppKit
import SwiftUI
import Testing
import TimelineSpikeCore
@testable import TimelineSpikeApp

/// The candidate has to reach the harness through the seam the console uses, not only through
/// the AppKit class the other tests drive directly.
@MainActor
@Suite("Renderer seam", .serialized)
struct RendererSeamTests {
    @Test("The catalogue lists the AppKit candidate")
    func catalogueContainsTheCandidate() {
        let ids = RendererCatalog.all.map(\.id)
        #expect(ids.contains(AppKitTableRenderer.rendererID))
        // The placeholder stays first, so the console still opens on the wiring demo and a
        // recorded run is always a deliberate choice.
        #expect(RendererCatalog.default.id == "placeholder")
    }

    @Test("Mounting the candidate through SwiftUI reaches the probe")
    func mountsThroughSwiftUI() {
        _ = NSApplication.shared
        let harness = SpikeHarness(
            configuration: HarnessConfiguration(
                seed: HarnessConfiguration.default.seed,
                initialEventCount: 500,
                mutation: .default,
                pagination: PaginationDriverConfiguration(isAutomatic: false)
            )
        )
        let descriptor = RendererDescriptor(AppKitTableRenderer.self)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 860),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let host = NSHostingView(rootView: descriptor.makeView(harness: harness))
        host.frame = NSRect(x: 0, y: 0, width: 1080, height: 860)
        window.contentView?.addSubview(host)
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()

        // The representable mounted, laid out, and reported its geometry: the whole seam.
        #expect(!harness.probe.visibleIDs.isEmpty)
        #expect(harness.probe.trackedID != nil)
        #expect(harness.probe.trackedOffset != nil)
    }
}

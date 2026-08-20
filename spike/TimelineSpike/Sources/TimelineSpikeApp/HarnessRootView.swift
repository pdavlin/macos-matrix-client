import SwiftUI
import TimelineSpikeCore

/// Timeline on the left, console on the right, HUD floating over the timeline.
///
/// The HUD is an overlay rather than a sibling so the timeline gets the full width it would
/// have in the real app. The console is a plain sidebar: this window is a measurement rig,
/// not a design study, so nothing here uses glass.
struct HarnessRootView: View {
    let harness: SpikeHarness
    @State private var renderer: RendererDescriptor = RendererCatalog.default

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                renderer.makeView(harness: harness)
                    .id(renderer.id)
                HUDView(snapshot: harness.hud, rendererName: renderer.displayName)
                    .padding(12)
                    .allowsHitTesting(false)
            }
            .frame(minWidth: 480)

            Divider()

            ControlPanelView(harness: harness, renderer: $renderer)
                .frame(width: 340)
        }
        .background(DisplayLinkHost(harness: harness).frame(width: 0, height: 0))
        .onAppear { harness.activeRenderer = renderer }
        .onChange(of: renderer) { _, newValue in
            harness.activeRenderer = newValue
            harness.resetInstrumentation()
        }
    }
}

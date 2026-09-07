import SwiftUI
import TimelineSpikeCore

/// Timeline on the left, console on the right, HUD floating over the timeline.
///
/// The HUD is an overlay rather than a sibling so the timeline gets the full width it would
/// have in the real app. The console is a plain sidebar: this window is a measurement rig,
/// not a design study, so nothing here uses glass.
struct HarnessRootView: View {
    let harness: SpikeHarness
    /// Non-nil when the process was started with `--scenario`; the runner picks
    /// the renderer and drives the window, and it starts once the view is up.
    let runnerOptions: RunnerOptions?

    @State private var renderer: RendererDescriptor
    @State private var runner: ScenarioRunner?

    init(harness: SpikeHarness, runnerOptions: RunnerOptions?) {
        self.harness = harness
        self.runnerOptions = runnerOptions
        let selected = runnerOptions
            .flatMap { RendererCatalog.renderer(withID: $0.rendererID) }
            ?? RendererCatalog.default
        _renderer = State(initialValue: selected)
    }

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
        .onAppear {
            harness.activeRenderer = renderer
            guard let runnerOptions, runner == nil else { return }
            let started = ScenarioRunner(harness: harness, options: runnerOptions)
            runner = started
            started.start()
        }
        .onChange(of: renderer) { _, newValue in
            harness.activeRenderer = newValue
            harness.resetInstrumentation()
        }
    }
}

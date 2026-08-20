import SwiftUI
import TimelineSpikeCore

/// The operator console. Everything the measurement protocol in SCENARIOS.md needs is
/// reachable from here or from the Spike menu.
struct ControlPanelView: View {
    let harness: SpikeHarness
    @Binding var renderer: RendererDescriptor

    @State private var seedText: String
    @State private var eventCountText: String
    @State private var mutationsPerTick: Double
    @State private var ticksPerSecond: Double
    @State private var onScreenBias: Double
    @State private var batchSize: Double
    @State private var automaticPagination: Bool
    @State private var settleTicks: Int

    init(harness: SpikeHarness, renderer: Binding<RendererDescriptor>) {
        self.harness = harness
        self._renderer = renderer
        let configuration = harness.configuration
        _seedText = State(initialValue: String(configuration.seed))
        _eventCountText = State(initialValue: String(configuration.initialEventCount))
        _mutationsPerTick = State(initialValue: Double(configuration.mutation.mutationsPerTick))
        _ticksPerSecond = State(initialValue: configuration.mutation.ticksPerSecond)
        _onScreenBias = State(initialValue: configuration.mutation.onScreenBias)
        _batchSize = State(initialValue: Double(configuration.pagination.batchSize))
        _automaticPagination = State(initialValue: configuration.pagination.isAutomatic)
        _settleTicks = State(initialValue: configuration.driftSettleTicks)
    }

    var body: some View {
        Form {
            Section("Renderer") {
                Picker("Candidate", selection: $renderer) {
                    ForEach(RendererCatalog.all) { descriptor in
                        Text(descriptor.displayName).tag(descriptor)
                    }
                }
                Text(renderer.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Scenario") {
                TextField("Label", text: Binding(
                    get: { harness.scenarioLabel },
                    set: { harness.scenarioLabel = $0 }
                ))
                Text("Written into the JSON report. Use the names in spike/SCENARIOS.md.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Timeline") {
                TextField("Seed", text: $seedText)
                TextField("Events", text: $eventCountText)
                Button("Regenerate") { regenerate() }
                Text("Regenerating resets the store, the drivers and the instruments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Mutation driver") {
                LabeledContent("Per tick") {
                    Slider(value: $mutationsPerTick, in: 0 ... 40, step: 1) {
                        Text("\(Int(mutationsPerTick))")
                    }
                }
                Text("\(Int(mutationsPerTick)) mutations per tick")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Rate Hz") {
                    Slider(value: $ticksPerSecond, in: 1 ... 60, step: 1)
                }
                Text(rateDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("On-screen bias") {
                    Slider(value: $onScreenBias, in: 0 ... 1)
                }
                Text("Slots 0 and 1 always hit on-screen and off-screen respectively.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(harness.isMutating ? "Stop storm" : "Start storm") {
                        applyDriverSettings()
                        harness.toggleMutating()
                    }
                    Button("Mutate once") {
                        applyDriverSettings()
                        harness.mutateOnce()
                    }
                }
            }

            Section("Back-pagination") {
                LabeledContent("Batch") {
                    Slider(value: $batchSize, in: 10 ... 200, step: 10)
                }
                Text("\(Int(batchSize)) events per prepend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Automatic near top", isOn: $automaticPagination)
                Button("Prepend now") {
                    applyDriverSettings()
                    harness.prependNow()
                }
            }

            Section("Instruments") {
                Stepper(
                    "Drift settle window: \(settleTicks) frames",
                    value: $settleTicks,
                    in: 1 ... 12
                )
                Text("Leave this at 3 unless SCENARIOS.md §10 says otherwise. Changing it "
                    + "clears the drift accumulators, because samples taken with two "
                    + "windows are two measurements.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reset instruments") { harness.resetInstrumentation() }
                Button("Dump stats to JSON") { harness.dumpReport() }
                // Shown so the operator can confirm two dumps came from the same row
                // workload without opening the JSON.
                LabeledContent("Workload", value: WorkloadFingerprint.value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = harness.lastReportURL {
                    Text(url.path)
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                if let error = harness.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: mutationsPerTick) { _, _ in applyDriverSettings() }
        .onChange(of: ticksPerSecond) { _, _ in applyDriverSettings() }
        .onChange(of: onScreenBias) { _, _ in applyDriverSettings() }
        .onChange(of: batchSize) { _, _ in applyDriverSettings() }
        .onChange(of: automaticPagination) { _, _ in applyDriverSettings() }
        .onChange(of: settleTicks) { _, newValue in harness.updateDriftSettleTicks(newValue) }
    }

    private var rateDescription: String {
        let total = mutationsPerTick * ticksPerSecond
        return "\(Int(ticksPerSecond)) Hz, about \(Int(total)) mutations per second"
    }

    private func applyDriverSettings() {
        harness.updateDriverConfiguration(
            mutation: MutationDriverConfiguration(
                mutationsPerTick: Int(mutationsPerTick),
                ticksPerSecond: ticksPerSecond,
                onScreenBias: onScreenBias,
                editShare: harness.configuration.mutation.editShare
            ),
            pagination: PaginationDriverConfiguration(
                batchSize: Int(batchSize),
                triggerDistance: harness.configuration.pagination.triggerDistance,
                minimumInterval: harness.configuration.pagination.minimumInterval,
                isAutomatic: automaticPagination
            )
        )
    }

    private func regenerate() {
        guard let seed = UInt64(seedText.trimmingCharacters(in: .whitespaces)),
              let count = Int(eventCountText.trimmingCharacters(in: .whitespaces)),
              count > 0 else {
            return
        }
        applyDriverSettings()
        harness.rebuild(
            with: HarnessConfiguration(
                seed: seed,
                initialEventCount: count,
                mutation: harness.configuration.mutation,
                pagination: harness.configuration.pagination,
                driftSettleTicks: settleTicks
            )
        )
    }
}

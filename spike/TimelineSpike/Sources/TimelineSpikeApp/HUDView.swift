import SwiftUI
import TimelineSpikeCore

/// The on-screen readout.
///
/// It reads `harness.hud`, a snapshot refreshed at 5 Hz, rather than the live statistics.
/// Binding the HUD to every display tick would make the instrument perturb the thing it
/// measures.
struct HUDView: View {
    let snapshot: HUDSnapshot
    let rendererName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(snapshot.isRecording ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(rendererName)
                    .font(.system(size: 11, weight: .semibold))
            }

            section("frame ms") {
                metric("p50", value: format(snapshot.p50))
                metric("p95", value: format(snapshot.p95))
                metric("p99", value: format(snapshot.p99))
                metric("worst", value: format(snapshot.worst))
                metric("nominal", value: format(snapshot.nominalMilliseconds))
                metric("hitches", value: "\(snapshot.hitchCount)")
                metric("frames", value: "\(snapshot.sampleCount)")
            }

            section("anchor drift pt") {
                driftMetrics("prepend", snapshot.prependDrift)
                driftMetrics("mutation", snapshot.mutationDrift)
                metric("discarded", value: "\(snapshot.discardedDriftSampleCount)")
            }

            section("timeline") {
                metric("loaded", value: "\(snapshot.loadedEventCount)")
                metric("oldest idx", value: "\(snapshot.oldestIndex)")
                metric("visible", value: "\(snapshot.visibleCount)")
                metric("tracked", value: snapshot.trackedID.map(\.description) ?? "-")
                metric("mutations", value: "\(snapshot.mutationCount)")
                metric("prepends", value: "\(snapshot.prependBatchCount)")
            }
        }
        .padding(12)
        .frame(width: 210, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        }
    }

    @ViewBuilder
    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func metric(_ name: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .monospacedDigit()
        }
        .font(.system(size: 11))
    }

    @ViewBuilder
    private func driftMetrics(_ name: String, _ accumulator: DriftAccumulator) -> some View {
        metric(
            name,
            value: accumulator.count == 0
                ? "-"
                : "\(format(accumulator.meanMagnitude)) / \(format(accumulator.worstMagnitude))"
        )
        metric(
            "\(name) stable",
            value: accumulator.count == 0
                ? "-"
                : "\(accumulator.stableCount)/\(accumulator.count)"
        )
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

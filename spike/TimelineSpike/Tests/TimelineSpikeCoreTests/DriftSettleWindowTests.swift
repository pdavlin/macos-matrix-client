import Foundation
import Testing
@testable import TimelineSpikeCore

@Suite("Drift settle window")
@MainActor
struct DriftSettleWindowTests {
    private func probeTracking(_ id: EventID, at offset: Double, settleTicks: Int) -> AnchorProbe {
        let probe = AnchorProbe(settleTicks: settleTicks)
        probe.reportVisible([EventID(id.rawValue - 1), id, EventID(id.rawValue + 1)], range: nil)
        probe.reportOffset(offset, for: id)
        return probe
    }

    @Test("The default window is three frames")
    func defaultIsThree() {
        #expect(AnchorProbe.defaultSettleTicks == 3)
        #expect(AnchorProbe().settleTicks == 3)
        #expect(HarnessConfiguration.default.driftSettleTicks == 3)
    }

    @Test("A longer window holds the sample open for exactly that many frames")
    func longerWindowHoldsTheSample() {
        let probe = probeTracking(EventID(5), at: 100, settleTicks: 6)
        probe.beginSample(kind: .mutation)
        probe.reportOffset(112, for: EventID(5))

        for tick in 1 ... 5 {
            probe.settle()
            #expect(probe.mutationDrift.count == 0, "closed early on tick \(tick)")
        }
        probe.settle()
        #expect(probe.mutationDrift.count == 1)
        #expect(abs(probe.mutationDrift.worstMagnitude - 12) < 0.001)
    }

    @Test("A longer window records the offset that was last reported, not an earlier one")
    func longerWindowReadsTheSettledOffset() {
        let probe = probeTracking(EventID(5), at: 100, settleTicks: 5)
        probe.beginSample(kind: .prepend)

        // A renderer whose layout converges over several frames: a candidate that jumps and
        // then corrects reads as stable at a long window and as a jump at a short one. This
        // is exactly why the window is recorded in the report.
        let trajectory: [Double] = [140, 118, 104, 100.2, 100.1]
        for offset in trajectory {
            probe.reportOffset(offset, for: EventID(5))
            probe.settle()
        }
        #expect(probe.prependDrift.count == 1)
        #expect(abs(probe.prependDrift.worstMagnitude - 0.1) < 0.001)
        #expect(probe.prependDrift.stableCount == 1)
    }

    @Test("The same trajectory at the default window scores the mid-flight position")
    func shortWindowSeesTheJump() {
        let probe = probeTracking(EventID(5), at: 100, settleTicks: 3)
        probe.beginSample(kind: .prepend)
        for offset in [140.0, 118.0, 104.0] {
            probe.reportOffset(offset, for: EventID(5))
            probe.settle()
        }
        #expect(probe.prependDrift.count == 1)
        #expect(abs(probe.prependDrift.worstMagnitude - 4) < 0.001)
        #expect(probe.prependDrift.stableCount == 0)
    }

    @Test("A window below one frame is refused")
    func windowIsClamped() {
        #expect(AnchorProbe(settleTicks: 0).settleTicks == 1)
        #expect(AnchorProbe(settleTicks: -4).settleTicks == 1)

        let probe = AnchorProbe()
        probe.settleTicks = 0
        #expect(probe.settleTicks == 1)
        #expect(HarnessConfiguration(driftSettleTicks: 0).driftSettleTicks == 1)
    }

    @Test("A one-frame window still needs a frame before it closes")
    func oneFrameWindowClosesOnTheNextTick() {
        let probe = probeTracking(EventID(7), at: 50, settleTicks: 1)
        probe.beginSample(kind: .mutation)
        #expect(probe.hasPendingSample)
        probe.reportOffset(50, for: EventID(7))
        probe.settle()
        #expect(probe.mutationDrift.count == 1)
    }

    @Test("The harness applies the configured window to its probe")
    func harnessAppliesTheConfiguration() {
        let harness = SpikeHarness(
            configuration: HarnessConfiguration(
                seed: 21,
                initialEventCount: 100,
                driftSettleTicks: 7
            )
        )
        #expect(harness.probe.settleTicks == 7)

        harness.rebuild(
            with: HarnessConfiguration(
                seed: 21,
                initialEventCount: 100,
                driftSettleTicks: 4
            )
        )
        #expect(harness.probe.settleTicks == 4)
    }

    @Test("Changing the window clears the accumulators rather than mixing measurements")
    func changingTheWindowResetsDrift() {
        let harness = SpikeHarness(
            configuration: HarnessConfiguration(seed: 22, initialEventCount: 100)
        )
        harness.probe.reportVisible([EventID(1), EventID(2), EventID(3)], range: 1 ..< 4)
        harness.probe.reportOffset(80, for: EventID(2))
        harness.probe.beginSample(kind: .prepend)
        harness.probe.reportOffset(95, for: EventID(2))
        for _ in 0 ..< harness.probe.settleTicks { harness.probe.settle() }
        #expect(harness.probe.prependDrift.count == 1)

        harness.updateDriftSettleTicks(6)
        #expect(harness.probe.settleTicks == 6)
        #expect(harness.probe.prependDrift.count == 0)
        #expect(harness.configuration.driftSettleTicks == 6)
    }

    @Test("Setting the window to the value it already has is a no-op")
    func idempotentUpdateKeepsSamples() {
        let harness = SpikeHarness(
            configuration: HarnessConfiguration(seed: 23, initialEventCount: 100)
        )
        harness.probe.reportVisible([EventID(1), EventID(2), EventID(3)], range: 1 ..< 4)
        harness.probe.reportOffset(80, for: EventID(2))
        harness.probe.beginSample(kind: .mutation)
        harness.probe.reportOffset(80, for: EventID(2))
        for _ in 0 ..< harness.probe.settleTicks { harness.probe.settle() }

        harness.updateDriftSettleTicks(AnchorProbe.defaultSettleTicks)
        #expect(harness.probe.mutationDrift.count == 1)
    }
}

@Suite("Report self-description")
@MainActor
struct ReportSelfDescriptionTests {
    @Test("The report carries the workload fingerprint and the settle window")
    func reportCarriesTheWorkload() {
        let harness = SpikeHarness(
            configuration: HarnessConfiguration(
                seed: 31,
                initialEventCount: 120,
                driftSettleTicks: 5
            )
        )
        let report = harness.makeReport()
        #expect(report.workloadFingerprint == WorkloadFingerprint.value)
        #expect(report.configuration.driftSettleTicks == 5)
    }

    @Test("Both fields survive a JSON round trip")
    func fieldsEncodeAndDecode() throws {
        let harness = SpikeHarness(
            configuration: HarnessConfiguration(
                seed: 32,
                initialEventCount: 120,
                driftSettleTicks: 6
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(harness.makeReport())
        let decoded = try JSONDecoder().decode(DumpProbe.self, from: data)
        #expect(decoded.workloadFingerprint == WorkloadFingerprint.value)
        #expect(decoded.configuration.driftSettleTicks == 6)
    }

    @Test("A configuration written before the window was configurable still decodes")
    func legacyConfigurationDecodes() throws {
        let json = """
        {
          "seed": 42,
          "initialEventCount": 500,
          "mutation": {
            "mutationsPerTick": 6,
            "ticksPerSecond": 10,
            "onScreenBias": 0.5,
            "editShare": 0.5
          },
          "pagination": {
            "batchSize": 50,
            "triggerDistance": 600,
            "minimumInterval": 0.35,
            "isAutomatic": true
          }
        }
        """
        let configuration = try JSONDecoder().decode(
            HarnessConfiguration.self,
            from: Data(json.utf8)
        )
        #expect(configuration.driftSettleTicks == AnchorProbe.defaultSettleTicks)
        #expect(configuration.seed == 42)
    }

    /// Decodes only the two fields under test, so the assertion does not depend on the rest
    /// of the report shape.
    private struct DumpProbe: Decodable {
        var workloadFingerprint: String
        var configuration: HarnessConfiguration
    }
}

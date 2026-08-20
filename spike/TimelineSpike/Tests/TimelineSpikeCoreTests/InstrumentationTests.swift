import Foundation
import Testing
@testable import TimelineSpikeCore

@Suite("Frame statistics")
struct FrameStatisticsTests {
    @Test("An empty recorder reports zeros rather than trapping")
    func emptyIsSafe() {
        let statistics = FrameStatistics()
        #expect(statistics.sampleCount == 0)
        #expect(statistics.p50 == 0)
        #expect(statistics.p95 == 0)
        #expect(statistics.hitchCount == 0)
        #expect(statistics.meanMilliseconds == 0)
        #expect(statistics.hitchRate == 0)
    }

    @Test("Percentiles land in the right bucket")
    func percentilesAreCorrect() {
        var statistics = FrameStatistics(nominalMilliseconds: 8.33)
        // 90 samples at 8 ms, 10 at 40 ms.
        for _ in 0 ..< 90 { statistics.record(interval: 8.0, nominal: 8.33) }
        for _ in 0 ..< 10 { statistics.record(interval: 40.0, nominal: 8.33) }

        #expect(statistics.sampleCount == 100)
        // Bucket width is 0.25 ms, so the reported value is the bucket's upper edge.
        #expect(abs(statistics.p50 - 8.25) < 0.001)
        #expect(abs(statistics.p95 - 40.25) < 0.001)
        #expect(abs(statistics.worstMilliseconds - 40.0) < 0.001)
        #expect(abs(statistics.meanMilliseconds - 11.2) < 0.001)
    }

    @Test("A hitch is a frame over twice the nominal interval")
    func hitchCounting() {
        var statistics = FrameStatistics(nominalMilliseconds: 8.0)
        statistics.record(interval: 8.0, nominal: 8.0)
        statistics.record(interval: 15.9, nominal: 8.0)
        statistics.record(interval: 16.1, nominal: 8.0)
        statistics.record(interval: 100.0, nominal: 8.0)
        #expect(statistics.hitchCount == 2)
        #expect(abs(statistics.hitchRate - 0.5) < 0.001)
    }

    @Test("Values past the histogram range still count and still report")
    func overflowIsHandled() {
        var statistics = FrameStatistics(nominalMilliseconds: 8.0)
        for _ in 0 ..< 9 { statistics.record(interval: 8.0, nominal: 8.0) }
        statistics.record(interval: 900.0, nominal: 8.0)
        #expect(statistics.sampleCount == 10)
        #expect(statistics.overflowCount == 1)
        #expect(abs(statistics.worstMilliseconds - 900.0) < 0.001)
        #expect(abs(statistics.percentile(1.0) - 900.0) < 0.001)
    }

    @Test("Non-positive and non-finite intervals are dropped")
    func garbageIsRejected() {
        var statistics = FrameStatistics()
        statistics.record(interval: 0, nominal: 8.0)
        statistics.record(interval: -3, nominal: 8.0)
        statistics.record(interval: .nan, nominal: 8.0)
        statistics.record(interval: .infinity, nominal: 8.0)
        #expect(statistics.sampleCount == 0)
    }

    @Test("Reset clears the histogram but keeps the nominal interval")
    func resetKeepsNominal() {
        var statistics = FrameStatistics(nominalMilliseconds: 8.33)
        for _ in 0 ..< 50 { statistics.record(interval: 30, nominal: 8.33) }
        statistics.reset()
        #expect(statistics.sampleCount == 0)
        #expect(statistics.hitchCount == 0)
        #expect(abs(statistics.nominalMilliseconds - 8.33) < 0.001)
    }

    @Test("The summary is the values the report exports")
    func summaryMatches() {
        var statistics = FrameStatistics(nominalMilliseconds: 8.0)
        for _ in 0 ..< 100 { statistics.record(interval: 8.0, nominal: 8.0) }
        let summary = statistics.summary
        #expect(summary.sampleCount == 100)
        #expect(summary.hitchCount == 0)
        #expect(abs(summary.p99Milliseconds - statistics.p99) < 0.001)
        #expect(summary.percentileResolutionMilliseconds == FrameStatistics.bucketWidthMilliseconds)
    }
}

@Suite("Anchor probe")
@MainActor
struct AnchorProbeTests {
    private func settle(_ probe: AnchorProbe) {
        for _ in 0 ..< probe.settleTicks {
            probe.settle()
        }
    }

    @Test("The tracked target is the middle visible item")
    func tracksTheMiddle() {
        let probe = AnchorProbe()
        probe.reportVisible([EventID(10), EventID(11), EventID(12)], range: 10 ..< 13)
        #expect(probe.trackedID == EventID(11))
        #expect(probe.visibleRange == 10 ..< 13)
    }

    @Test("The target survives a scroll that keeps it on screen")
    func targetIsSticky() {
        let probe = AnchorProbe()
        probe.reportVisible([EventID(10), EventID(11), EventID(12)], range: 10 ..< 13)
        probe.reportVisible([EventID(11), EventID(12), EventID(13)], range: 11 ..< 14)
        #expect(probe.trackedID == EventID(11))
    }

    @Test("Offsets from other items are ignored")
    func onlyTheTargetIsRecorded() {
        let probe = AnchorProbe()
        probe.reportVisible([EventID(1), EventID(2), EventID(3)], range: 1 ..< 4)
        probe.reportOffset(120, for: EventID(3))
        #expect(probe.trackedOffset == nil)
        probe.reportOffset(90, for: EventID(2))
        #expect(probe.trackedOffset == 90)
    }

    @Test("A sample closes after the settle window with the movement in points")
    func measuresDrift() {
        let probe = AnchorProbe()
        probe.reportVisible([EventID(1), EventID(2), EventID(3)], range: 1 ..< 4)
        probe.reportOffset(200, for: EventID(2))

        #expect(probe.beginSample(kind: .prepend))
        #expect(probe.hasPendingSample)
        probe.reportOffset(212.5, for: EventID(2))

        probe.settle()
        #expect(probe.prependDrift.count == 0, "the sample must not close early")
        probe.settle()
        probe.settle()

        #expect(probe.prependDrift.count == 1)
        #expect(abs(probe.prependDrift.worstMagnitude - 12.5) < 0.001)
        #expect(probe.mutationDrift.count == 0)
        #expect(probe.lastSample?.signedDelta == 12.5)
    }

    @Test("Movement under half a point counts as stable")
    func stabilityThreshold() {
        let probe = AnchorProbe()
        probe.reportVisible([EventID(1), EventID(2), EventID(3)], range: 1 ..< 4)
        probe.reportOffset(100, for: EventID(2))
        probe.beginSample(kind: .mutation)
        probe.reportOffset(100.2, for: EventID(2))
        settle(probe)
        #expect(probe.mutationDrift.count == 1)
        #expect(probe.mutationDrift.stableCount == 1)
        #expect(probe.mutationDrift.stableFraction == 1)
    }

    @Test("A sample is discarded, not scored, when the target leaves the viewport")
    func discardsLostTargets() {
        let probe = AnchorProbe()
        probe.reportVisible([EventID(1), EventID(2), EventID(3)], range: 1 ..< 4)
        probe.reportOffset(100, for: EventID(2))
        probe.beginSample(kind: .prepend)
        probe.reportVisible([EventID(80), EventID(81), EventID(82)], range: 80 ..< 83)
        settle(probe)
        #expect(probe.prependDrift.count == 0)
        #expect(probe.discardedSampleCount == 1)
    }

    @Test("Sampling before the first layout is refused")
    func refusesBeforeLayout() {
        let probe = AnchorProbe()
        #expect(probe.beginSample(kind: .mutation) == false)
        #expect(probe.hasPendingSample == false)
    }

    @Test("Reset clears the accumulators and any pending sample")
    func resetClearsEverything() {
        let probe = AnchorProbe()
        probe.reportVisible([EventID(1), EventID(2), EventID(3)], range: 1 ..< 4)
        probe.reportOffset(10, for: EventID(2))
        probe.beginSample(kind: .prepend)
        probe.reportOffset(40, for: EventID(2))
        settle(probe)
        #expect(probe.prependDrift.count == 1)

        probe.reset()
        #expect(probe.prependDrift.count == 0)
        #expect(probe.lastSample == nil)
        #expect(probe.hasPendingSample == false)
        #expect(probe.discardedSampleCount == 0)
    }
}

@Suite("Harness wiring")
@MainActor
struct SpikeHarnessTests {
    @Test("A prepend snapshots the anchor before the store changes")
    func prependSnapshotsTheAnchor() {
        let harness = SpikeHarness(
            configuration: HarnessConfiguration(seed: 9, initialEventCount: 300)
        )
        let items = harness.store.items
        harness.probe.reportVisible(items[100 ... 102].map(\.id), range: 100 ..< 103)
        harness.probe.reportOffset(150, for: harness.probe.trackedID ?? EventID(0))

        harness.prependNow()
        #expect(harness.probe.hasPendingSample)
        #expect(harness.store.items.count == 350)

        harness.probe.reportOffset(150, for: harness.probe.trackedID ?? EventID(0))
        for _ in 0 ..< harness.probe.settleTicks { harness.probe.settle() }
        #expect(harness.probe.prependDrift.count == 1)
        #expect(harness.probe.prependDrift.worstMagnitude == 0)
    }

    @Test("A manual mutation tick runs against the reported viewport")
    func mutationUsesTheReportedViewport() {
        let harness = SpikeHarness(
            configuration: HarnessConfiguration(seed: 11, initialEventCount: 400)
        )
        let items = harness.store.items
        harness.probe.reportVisible(items[50 ..< 70].map(\.id), range: 50 ..< 70)
        harness.mutateOnce()
        #expect(harness.store.appliedMutationCount > 0)
        #expect(harness.probe.hasPendingSample == false, "no anchor offset was reported yet")
    }

    @Test("The report carries the configuration that produced it")
    func reportIsSelfDescribing() {
        let configuration = HarnessConfiguration(seed: 4_242, initialEventCount: 500)
        let harness = SpikeHarness(configuration: configuration)
        harness.scenarioLabel = "S1-cold-scroll"
        harness.prependNow()

        let report = harness.makeReport()
        #expect(report.scenario == "S1-cold-scroll")
        #expect(report.configuration.seed == 4_242)
        #expect(report.configuration.initialEventCount == 500)
        #expect(report.counters.loadedEventCount == 550)
        #expect(report.counters.manualPrependCount == 1)
        #expect(report.counters.oldestIndex == -50)
        #expect(report.rendererID == "unknown")
    }

    @Test("Rebuilding regenerates the timeline and clears the instruments")
    func rebuildResets() {
        let harness = SpikeHarness(
            configuration: HarnessConfiguration(seed: 1, initialEventCount: 200)
        )
        harness.prependNow()
        #expect(harness.store.items.count == 250)

        harness.rebuild(with: HarnessConfiguration(seed: 2, initialEventCount: 120))
        #expect(harness.store.items.count == 120)
        #expect(harness.store.oldestIndex == 0)
        #expect(harness.configuration.seed == 2)
        #expect(harness.probe.prependDrift.count == 0)
    }

    @Test("The report encodes to JSON")
    func reportEncodes() throws {
        let harness = SpikeHarness(
            configuration: HarnessConfiguration(seed: 3, initialEventCount: 120)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(harness.makeReport())
        #expect(data.count > 0)
        let decoded = try JSONDecoder().decode(
            [String: AnyCodableProbe].self,
            from: data
        )
        #expect(decoded.keys.contains("frame"))
        #expect(decoded.keys.contains("prependDrift"))
        #expect(decoded.keys.contains("configuration"))
    }
}

/// A decoding stand-in used only to assert that the report's top-level keys exist. It
/// deliberately decodes nothing: the point is the shape, not the values.
private struct AnyCodableProbe: Decodable {
    init(from decoder: Decoder) throws {}
}

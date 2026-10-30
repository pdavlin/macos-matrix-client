#if DEBUG
    import Foundation
    import Models
    import QuartzCore
    import TimelineSpikeCore
    import UIKit

    /// The gate scenarios (MATRIX-87). Names follow `spike/SCENARIOS.md`
    /// where a Mac scenario has an iOS twin; the rest are iOS-only.
    extension TimelineGateRunner {
        /// Counters at the start of a scenario, so a report covers only its
        /// own window.
        struct ScenarioStart {
            let misses: Int
            let lookups: Int
            let mutations: Int
            let fetches: Int
            let layoutPasses: Int
        }

        func beginScenario() -> ScenarioStart {
            resetProbe()
            recorder.resetStatistics()
            let stats = controller.heightCache.stats
            return ScenarioStart(
                misses: stats.misses,
                lookups: stats.lookups,
                mutations: store.appliedMutationCount,
                fetches: feed.fetchRequestCount,
                layoutPasses: layoutProbe.passes
            )
        }

        // MARK: - Cold load

        /// The first layout of the 10k-event timeline: every row measured
        /// once, offscreen, synchronously. Scored: one measure per row.
        func coldLoad() -> TimelineGateReport {
            let start = beginScenario()
            let pass = layoutPass(to: TimelineGatePlan.viewport)
            return report(
                "cold-load",
                since: start,
                passes: [pass],
                verdicts: [
                    TimelineGateVerdict("cold-load.remeasured", Double(pass.remeasured), "<=", Double(pass.rows)),
                ]
            )
        }

        // MARK: - S1: scroll

        /// A steady sweep from the newest end (S1). Every height is cached,
        /// so scrolling must never measure a row. Frame times on a device.
        func runSweep() async -> TimelineGateReport {
            scroll(toOriginY: 0)
            await frames(10)
            let start = beginScenario()
            let isDevice = environment?.kind == "device"
            await sweep(seconds: isDevice ? TimelineGatePlan.deviceSweepSeconds : TimelineGatePlan.simulatorSweepSeconds)
            await frames(5)
            let remeasured = controller.heightCache.stats.misses - start.misses
            return report(
                "s1",
                since: start,
                measuresFrames: true,
                verdicts: [
                    TimelineGateVerdict("s1.remeasured", Double(remeasured), "==", 0),
                    TimelineGateVerdict(
                        "s1.layoutPrepares",
                        Double(layoutProbe.passes - start.layoutPasses),
                        "<=",
                        TimelineGateBars.scrollLayoutPrepares
                    ),
                ]
            )
        }

        // MARK: - S2: mutation storm

        /// The Mac S2 workload, parked mid-timeline, with each tick held until
        /// the container is idle, so every count and position is
        /// deterministic. The drain still runs on its own display link.
        func runQuiescedStorm() async -> TimelineGateReport {
            await seek(toFraction: TimelineGatePlan.stormFraction)
            let start = beginScenario()
            var hold = TimelineGateMeasurements.AnchorHold()
            var drain = TimelineGateMeasurements.Drain(pacing: "quiesced")

            settlesProbe = false
            for _ in 0 ..< TimelineGatePlan.stormTicks {
                reportGeometry()
                let anchor = anchorEdge()
                probe.beginSample(kind: .mutation)
                feed.recordMutations(mutationDriver.step(store: store, visibleRange: probe.visibleRange))

                let wait = await quiesce()
                drain.ticks += 1
                drain.framesTotal += wait.frames
                drain.framesWorstPerTick = max(drain.framesWorstPerTick, wait.frames)
                drain.backlogWorst = max(drain.backlogWorst, wait.backlog)
                if !wait.drained { drain.stalledTicks += 1 }

                if let anchor, let after = edge(ofRowId: anchor.rowId) {
                    hold.record(Double(after - anchor.edge))
                }
                await settleProbe()
            }
            settlesProbe = true

            let mutations = store.appliedMutationCount - start.mutations
            let remeasured = controller.heightCache.stats.misses - start.misses
            let perMutation = mutations > 0 ? Double(remeasured) / Double(mutations) : 0
            return report(
                "s2-quiesced",
                since: start,
                anchorHold: hold,
                drain: drain,
                verdicts: [
                    TimelineGateVerdict("s2.anchorHoldWorst", hold.worstPoints, "<=", TimelineGateBars.stormAnchorHoldWorstPoints),
                    TimelineGateVerdict("s2.driftWorst", probe.mutationDrift.worstMagnitude, "<=", TimelineGateBars.stormDriftWorstPoints),
                    TimelineGateVerdict(
                        "s2.remeasuredPerMutation",
                        perMutation,
                        "<=",
                        TimelineGateBars.stormRemeasuresPerMutation
                    ),
                    TimelineGateVerdict("s2.stalledTicks", Double(drain.stalledTicks), "==", 0),
                ]
            )
        }

        /// The Mac S2 as the Mac runs it: ticks at the storm rate while the
        /// drain keeps up as it can. Device only, for frame times; no bars
        /// until a device baseline exists.
        func runPacedStorm() async -> TimelineGateReport {
            await seek(toFraction: TimelineGatePlan.stormFraction)
            let start = beginScenario()
            var drain = TimelineGateMeasurements.Drain(pacing: "paced")
            let interval = 1 / max(0.1, configuration.mutation.ticksPerSecond)
            var nextTick = CACurrentMediaTime()
            let end = nextTick + TimelineGatePlan.pacedStormSeconds

            while CACurrentMediaTime() < end {
                await nextFrame()
                if CACurrentMediaTime() >= nextTick {
                    // One sample at a time, as the Mac harness does.
                    if !probe.hasPendingSample {
                        probe.beginSample(kind: .mutation)
                    }
                    feed.recordMutations(mutationDriver.step(store: store, visibleRange: probe.visibleRange))
                    drain.ticks += 1
                    nextTick += interval
                }
                drain.backlogWorst = max(drain.backlogWorst, controller.pendingRowUpdates.count)
            }
            let wait = await quiesce()
            if !wait.drained { drain.stalledTicks += 1 }
            await frames(5)
            return report("s2-paced", since: start, measuresFrames: true, drain: drain, verdicts: [])
        }

        // MARK: - S4: prepend

        /// Twenty back-pagination batches with a tracked event on screen near
        /// the oldest end (S4). A prepend lands beyond the viewport, so every
        /// point of drift is anchoring failure.
        func runPrepends() async -> TimelineGateReport {
            await seek(toFraction: TimelineGatePlan.prependFraction)
            let start = beginScenario()
            let prependedBefore = store.prependedEventCount

            settlesProbe = false
            for _ in 0 ..< TimelineGatePlan.prependCount {
                reportGeometry()
                paginationDriver.prependNow(store: store)
                _ = await quiesce()
                await settleProbe()
            }
            settlesProbe = true
            await frames(5)

            let prepended = store.prependedEventCount - prependedBefore
            let remeasured = controller.heightCache.stats.misses - start.misses
            return report(
                "s4",
                since: start,
                verdicts: [
                    TimelineGateVerdict("s4.samples", Double(probe.prependDrift.count), "==", TimelineGateBars.prependSamples),
                    TimelineGateVerdict(
                        "s4.driftWorst",
                        probe.prependDrift.worstMagnitude,
                        "<=",
                        TimelineGateBars.prependDriftWorstPoints
                    ),
                    // Each new row once, plus at most the seam row per batch,
                    // whose sender header can change under its new neighbor.
                    TimelineGateVerdict(
                        "s4.remeasured",
                        Double(remeasured),
                        "<=",
                        Double(prepended + TimelineGatePlan.prependCount)
                    ),
                ]
            )
        }

        // MARK: - Width change

        /// A rotation at the full timeline, and back: the synchronous full
        /// re-measure MATRIX-85 listed. Scored on count (one pass per width
        /// change, not the two the Mac paid before MATRIX-59); the time is a
        /// simulator number and is recorded only.
        func runWidthChange() async -> TimelineGateReport {
            await frames(5)
            let start = beginScenario()
            let rotate = layoutPass(to: CGSize(width: TimelineGatePlan.rotatedWidth, height: TimelineGatePlan.viewport.height))
            await frames(5)
            let restore = layoutPass(to: TimelineGatePlan.viewport)
            await frames(5)
            return report(
                "width-change",
                since: start,
                passes: [rotate, restore],
                verdicts: [
                    TimelineGateVerdict("width-change.rotate.remeasured", Double(rotate.remeasured), "<=", Double(rotate.rows)),
                    TimelineGateVerdict("width-change.restore.remeasured", Double(restore.remeasured), "<=", Double(restore.rows)),
                ]
            )
        }

        // MARK: - Report

        func report(
            _ scenario: String,
            since start: ScenarioStart,
            measuresFrames: Bool = false,
            anchorHold: TimelineGateMeasurements.AnchorHold? = nil,
            drain: TimelineGateMeasurements.Drain? = nil,
            passes: [TimelineGateMeasurements.LayoutPass] = [],
            verdicts: [TimelineGateVerdict]
        ) -> TimelineGateReport {
            let environment = environment ?? TimelineGateEnvironment.current(screen: container.window?.windowScene?.screen, cadence: nil)
            let stats = controller.heightCache.stats
            let viewport = controller.collectionView.bounds.size
            return TimelineGateReport(
                generatedAt: Date(),
                scenario: scenario,
                rendererID: TimelineGateReport.rendererID,
                rendererName: TimelineGateReport.rendererName,
                workloadFingerprint: WorkloadFingerprint.value,
                timelineWidth: Double(viewport.width),
                timelineHeight: Double(viewport.height),
                environment: environment,
                configuration: configuration,
                frame: measuresFrames && environment.frameMetricsScored ? recorder.statistics.summary : nil,
                prependDrift: probe.prependDrift,
                mutationDrift: probe.mutationDrift,
                counters: TimelineGateReport.Counters(
                    loadedEventCount: store.items.count,
                    oldestIndex: store.oldestIndex,
                    newestIndex: store.newestIndex,
                    appliedMutationCount: store.appliedMutationCount,
                    manualPrependCount: paginationDriver.manualPrependCount,
                    automaticPrependCount: paginationDriver.automaticPrependCount,
                    prependedEventCount: store.prependedEventCount,
                    discardedDriftSampleCount: probe.discardedSampleCount
                ),
                host: TimelineGateReport.Host(
                    operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                    machineModel: environment.deviceModel,
                    processorCount: ProcessInfo.processInfo.processorCount
                ),
                ios: TimelineGateMeasurements(
                    rowCount: controller.rows.count,
                    mutationsApplied: store.appliedMutationCount - start.mutations,
                    remeasureCount: stats.misses - start.misses,
                    cacheLookups: stats.lookups - start.lookups,
                    driftSamples: driftSamples,
                    anchorHold: anchorHold,
                    drain: drain,
                    layoutPasses: passes,
                    layoutPrepares: layoutProbe.passes - start.layoutPasses,
                    fetchRequestCount: feed.fetchRequestCount - start.fetches
                ),
                verdicts: verdicts
            )
        }
    }
#endif

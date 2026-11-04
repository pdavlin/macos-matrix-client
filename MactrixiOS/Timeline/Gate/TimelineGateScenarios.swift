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
            let rowRereads: Int
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
                layoutPasses: layoutProbe.passes,
                rowRereads: layoutProbe.rowRereads
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
            await sweepReport("s1")
        }

        /// The S1 sweep with the viewport under the status bar, where every
        /// cell near the top edge gets a safe-area inset (MATRIX-98). The
        /// same bars as `s1`: before MATRIX-98 this read 50 layout passes.
        func runStatusBarSweep() async -> TimelineGateReport {
            placesViewportUnderStatusBar = true
            defer { placesViewportUnderStatusBar = false }
            return await sweepReport("s1-status-bar")
        }

        private func sweepReport(_ scenario: String) async -> TimelineGateReport {
            scroll(toOriginY: 0)
            await frames(10)
            let start = beginScenario()
            let isDevice = environment?.kind == "device"
            await sweep(seconds: isDevice ? TimelineGatePlan.deviceSweepSeconds : TimelineGatePlan.simulatorSweepSeconds)
            await frames(5)
            let remeasured = controller.heightCache.stats.misses - start.misses
            return report(
                scenario,
                since: start,
                measuresFrames: true,
                verdicts: [
                    TimelineGateVerdict("\(scenario).remeasured", Double(remeasured), "==", 0),
                    TimelineGateVerdict(
                        "\(scenario).layoutPrepares",
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

        /// A rotation at the full timeline, parked near the oldest end, and
        /// back (MATRIX-98). The pass that changes the width measures only the
        /// rows around the anchor; the drain measures the rest in its frame
        /// budget, and the anchor holds through all of it. Scored on the
        /// anchor and on count: at most one measure per row for the rotation,
        /// none for the way back, whose width the cache still holds. The
        /// longest main-thread block is a simulator number and is recorded
        /// only.
        func runWidthChange() async -> TimelineGateReport {
            await frames(5)
            let start = beginScenario()
            let rotate = await widthChange(to: CGSize(width: TimelineGatePlan.rotatedWidth, height: TimelineGatePlan.viewport.height))
            await frames(5)
            let restore = await widthChange(to: TimelineGatePlan.viewport)
            await frames(5)
            return report(
                "width-change",
                since: start,
                passes: [rotate, restore],
                verdicts: [
                    TimelineGateVerdict("width-change.rotate.remeasured", Double(rotate.remeasured), "<=", Double(rotate.rows)),
                    TimelineGateVerdict("width-change.restore.remeasured", Double(restore.remeasured), "==", 0),
                    TimelineGateVerdict("width-change.rotate.drained", rotate.drained == true ? 1 : 0, "==", 1),
                    TimelineGateVerdict("width-change.restore.drained", restore.drained == true ? 1 : 0, "==", 1),
                    TimelineGateVerdict(
                        "width-change.rotate.anchorDriftWorst",
                        rotate.anchorDrift?.worstPoints ?? .infinity,
                        "<=",
                        TimelineGateBars.widthChangeAnchorDriftWorstPoints
                    ),
                    TimelineGateVerdict(
                        "width-change.restore.anchorDriftWorst",
                        restore.anchorDrift?.worstPoints ?? .infinity,
                        "<=",
                        TimelineGateBars.widthChangeAnchorDriftWorstPoints
                    ),
                ]
            )
        }

        /// Resizes the viewport the way a rotation does, then follows the
        /// drain until every row is exact at the new width (MATRIX-98).
        ///
        /// Records the longest gap between two display-link callbacks from
        /// the frame before the change to the end of the drain, which is the
        /// longest the main thread was blocked, and the anchor row's movement
        /// on screen at every frame of it.
        func widthChange(to size: CGSize) async -> TimelineGateMeasurements.LayoutPass {
            let collectionView = controller.collectionView
            let fromWidth = collectionView.bounds.width
            await nextFrame()
            let anchor = anchorEdge()
            let missesBefore = controller.heightCache.stats.misses
            var previousFrame = CACurrentMediaTime()

            let started = CACurrentMediaTime()
            container.frame.size = size
            collectionView.frame = container.bounds
            collectionView.layoutIfNeeded()
            let synchronousSeconds = CACurrentMediaTime() - started
            let synchronousRemeasured = controller.heightCache.stats.misses - missesBefore

            var drift = TimelineGateMeasurements.AnchorHold()
            var longestBlock: CFTimeInterval = 0
            var drainFrames = 0
            var drained = false
            // The first frame after the change always counts: the gap before
            // it holds the pass that changed the width.
            repeat {
                if let anchor, let after = edge(ofRowId: anchor.rowId) {
                    drift.record(Double(after - anchor.edge))
                }
                await nextFrame()
                let now = CACurrentMediaTime()
                longestBlock = max(longestBlock, now - previousFrame)
                previousFrame = now
                if !controller.hasDrainWork, controller.rowUpdateDisplayLink == nil {
                    drained = true
                } else {
                    drainFrames += 1
                }
            } while !drained && drainFrames < TimelineGatePlan.widthDrainFrameCap
            if let anchor, let after = edge(ofRowId: anchor.rowId) {
                drift.record(Double(after - anchor.edge))
            }
            let seconds = CACurrentMediaTime() - started
            let remeasured = controller.heightCache.stats.misses - missesBefore
            return TimelineGateMeasurements.LayoutPass(
                fromWidth: Double(fromWidth),
                toWidth: Double(size.width),
                rows: controller.rows.count,
                remeasured: remeasured,
                milliseconds: seconds * 1000,
                microsecondsPerRemeasure: remeasured > 0 ? seconds * 1_000_000 / Double(remeasured) : 0,
                synchronousRemeasured: synchronousRemeasured,
                synchronousMilliseconds: synchronousSeconds * 1000,
                drainFrames: drainFrames,
                drained: drained,
                longestBlockMilliseconds: longestBlock * 1000,
                anchorDrift: anchor == nil ? nil : drift
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
                    layoutRowRereads: layoutProbe.rowRereads - start.rowRereads,
                    fetchRequestCount: feed.fetchRequestCount - start.fetches
                ),
                verdicts: verdicts
            )
        }
    }
#endif

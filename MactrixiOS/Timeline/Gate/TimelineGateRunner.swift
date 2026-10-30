#if DEBUG
    import Models
    import QuartzCore
    import TimelineSpikeCore
    import Tokens
    import UIKit
    import Utils

    /// The pinned geometry and run lengths of the iOS gate (MATRIX-87).
    enum TimelineGatePlan {
        /// The timeline viewport every number is measured at. Heights are
        /// cached per width, so the width is an input to every count here.
        /// It fits inside the portrait safe area of every current iPhone: a
        /// viewport under the status bar or the home indicator gets its cells
        /// a safe-area inset, and every cell then reports a preferred height
        /// that disagrees with its measured one.
        static let viewport = CGSize(width: 390, height: 700)
        /// The width-change scenario's target: an iPhone rotated to landscape.
        static let rotatedWidth: CGFloat = 750
        /// Storm ticks in the quiesced storm: the Mac S2's 30s at 10Hz.
        static let stormTicks = 300
        static let pacedStormSeconds: TimeInterval = 30
        static let simulatorSweepSeconds: TimeInterval = 5
        static let deviceSweepSeconds: TimeInterval = 30
        /// The Mac runner's calibration spin.
        static let calibrationSeconds: TimeInterval = 2
        /// The Mac `ScrollDriver`'s reading speed: a screen every ~3 seconds.
        static let pointsPerSecond: CGFloat = 250
        static let prependCount = 20
        /// Where the Mac scenarios park: mid-timeline for the storm, near the
        /// oldest end for the prepends.
        static let stormFraction: CGFloat = 0.5
        static let prependFraction: CGFloat = 0.92
        /// Frames a quiesced wait gives the container before it counts the
        /// tick as stalled.
        static let quiesceFrameCap = 600
    }

    /// The bars the deterministic metrics are scored against (MATRIX-87).
    ///
    /// Only counts and anchor positions are barred. They come from the
    /// container's logic, not from the clock, so the simulator measures them
    /// exactly as a phone does. Frame times and wall times are recorded and
    /// never barred here: a simulator frame is a Mac GPU frame.
    enum TimelineGateBars {
        /// Every prepend produces a sample (the Mac gate's
        /// `PREPEND_SAMPLE_COUNT`).
        static let prependSamples = Double(TimelineGatePlan.prependCount)
        /// The Mac gate's prepend bar: a 0.0pt baseline with the probe's own
        /// half-point stability threshold (`PREPEND_DRIFT_TOLERANCE_PT`).
        static let prependDriftWorstPoints = DriftAccumulator.stabilityThreshold
        /// The container's anchor row stays put through every storm tick. The
        /// compensation promises exactly this; half a point is the probe's
        /// stability threshold.
        static let stormAnchorHoldWorstPoints = DriftAccumulator.stabilityThreshold
        /// Middle-row drift in the quiesced storm. It includes real content
        /// movement between the anchor row and the tracked row, so it is not
        /// an anchoring error. The bar is the recorded baseline's worst
        /// (282.0pt, identical in three runs, 2026-10-30) plus 50%: the
        /// MATRIX-60 "pinned reference runs with margin" option, with the
        /// margin there for a simulator runtime whose fonts wrap differently.
        static let stormDriftWorstPoints = 423.0
        /// Row measures per applied storm mutation. MATRIX-63 fingerprints
        /// skip height-neutral re-tallies, so the baseline is below one
        /// (1314 / 1800 = 0.730, identical in three runs, 2026-10-30). The
        /// bar is the baseline plus 0.05. A container that stopped honoring
        /// fingerprints measures every mutated row and reads near 1.0.
        static let stormRemeasuresPerMutation = 0.78
        /// Layout passes during a plain 5s scroll. Each pass walks every
        /// row's cached height. UIKit's self-sizing check on a newly visible
        /// cell runs some (3 in each of three runs, 2026-10-30), and when it
        /// does is UIKit's timing, not the container's. The bar catches a pass
        /// per cell or per frame: a viewport under a safe-area inset read 50.
        static let scrollLayoutPrepares = 10.0
    }

    /// Drives the production `TimelineCollectionController` through the gate
    /// scenarios on a synthetic feed, and reads its geometry and counters
    /// (MATRIX-87).
    ///
    /// The Mac gate's `ScenarioRunner` and `SpikeHarness` in one object, for
    /// UIKit. The workload, the drivers, the probe, and the frame recorder
    /// are the spike's own (`TimelineSpikeCore`), so both gates generate the
    /// same 10k events and score drift the same way.
    @MainActor
    final class TimelineGateRunner {
        struct Outcome {
            var reports: [TimelineGateReport]
            /// Why a device run refused to measure, or nil.
            var refusal: String?

            var verdicts: [TimelineGateVerdict] { reports.flatMap(\.verdicts) }
            var passed: Bool { refusal == nil && verdicts.allSatisfy(\.passed) }
        }

        let configuration: HarnessConfiguration
        let store: TimelineStore
        let feed: TimelineGateFeed
        let controller: TimelineCollectionController
        /// The pinned viewport. The host puts it in a window: the drain paces
        /// on a display link only when the collection view has one.
        let container: UIView

        let probe: AnchorProbe
        let recorder = FrameRecorder()
        let layoutProbe = TimelineGateLayoutProbe()
        let mutationDriver: MutationDriver
        let paginationDriver: PaginationDriver

        var environment: TimelineGateEnvironment?
        /// Per-frame work a scenario installs, run before the probe reads.
        var frameAction: (() -> Void)?
        /// Off while a quiesced scenario holds a sample open until the
        /// container is idle.
        var settlesProbe = true
        var driftSamples: [DriftSample] = []

        private var frameWaiters: [CheckedContinuation<Void, Never>] = []
        private var lastVisibleIDs: [EventID] = []
        private var closedSampleCount = 0

        init() {
            var configuration = HarnessConfiguration.default
            // Every scenario prepends on its own schedule, as on the Mac.
            configuration.pagination.isAutomatic = false
            self.configuration = configuration
            store = TimelineStore(seed: configuration.seed, initialEventCount: configuration.initialEventCount)
            feed = TimelineGateFeed(store: store)
            controller = TimelineCollectionController(
                feed: feed,
                rowContext: TimelineRowContext(
                    timeline: nil,
                    imageLoader: nil,
                    ownUserId: "@me:spike",
                    showsReadReceipts: false,
                    typography: .default,
                    retryPagination: {}
                )
            )
            probe = AnchorProbe(settleTicks: configuration.driftSettleTicks)
            mutationDriver = MutationDriver(seed: configuration.seed, configuration: configuration.mutation)
            paginationDriver = PaginationDriver(configuration: configuration.pagination)

            container = UIView(frame: CGRect(origin: .zero, size: TimelineGatePlan.viewport))
            container.clipsToBounds = true
            // Zero until the cold-load scenario sizes it, so the first
            // measuring layout pass is the one it times.
            controller.collectionView.frame = .zero
            container.addSubview(controller.collectionView)
            layoutProbe.source = controller
            controller.layout.heightSource = layoutProbe

            paginationDriver.willPrepend = { [weak self] in
                self?.probe.beginSample(kind: .prepend)
            }
            paginationDriver.didPrepend = { [weak self] range in
                self?.feed.recordPrepend(count: range.count)
            }
        }

        // MARK: - Run

        /// Runs every scenario in order on one timeline, as the Mac runner does.
        func run() async -> Outcome {
            recorder.pinnedHertz = PinnedCadence.hertz
            recorder.onTick = { [weak self] in self?.tick() }
            recorder.attach()
            defer {
                recorder.onTick = nil
                recorder.detach()
                controller.stopRowUpdateDrain()
            }

            let cold = coldLoad()
            await frames(10)

            let cadence = await calibrateCadence()
            let environment = TimelineGateEnvironment.current(screen: container.window?.windowScene?.screen, cadence: cadence)
            self.environment = environment
            var reports = [cold]
            reports[0].environment = environment

            if environment.kind == "device", !environment.frameMetricsScored {
                return Outcome(reports: reports, refusal: Self.refusalReason(environment))
            }

            await reports.append(runSweep())
            await reports.append(runQuiescedStorm())
            if environment.frameMetricsScored {
                await reports.append(runPacedStorm())
            }
            await reports.append(runPrepends())
            await reports.append(runWidthChange())
            return Outcome(reports: reports, refusal: nil)
        }

        private static func refusalReason(_ environment: TimelineGateEnvironment) -> String {
            guard environment.optimized else {
                return "an -Onone build: device frame numbers need an optimized build (spike/GATE.md, iOS)"
            }
            let measured = environment.cadence.map { $0.measuredHertz.formatted(.number.precision(.fractionLength(1))) } ?? "no"
            return "the display link delivered \(measured)Hz, not the pinned \(Int(PinnedCadence.hertz))Hz (spike/GATE.md, iOS)"
        }

        /// Spins the viewport for the calibration window and measures the
        /// cadence the pinned link delivered (MATRIX-64). A still viewport is
        /// no evidence about a moving one, so the spin scrolls.
        private func calibrateCadence() async -> CadenceMeasurement {
            scroll(toOriginY: 0)
            await frames(5)
            recorder.beginCalibration()
            await sweep(seconds: TimelineGatePlan.calibrationSeconds)
            return recorder.endCalibration()
        }

        // MARK: - Frames

        private func tick() {
            frameAction?()
            reportGeometry()
            if settlesProbe {
                probe.settle()
                collectClosedSample()
            }
            let waiters = frameWaiters
            frameWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }

        func nextFrame() async {
            await withCheckedContinuation { frameWaiters.append($0) }
        }

        func frames(_ count: Int) async {
            for _ in 0 ..< count {
                await nextFrame()
            }
        }

        private func collectClosedSample() {
            let closed = probe.prependDrift.count + probe.mutationDrift.count
            if closed > closedSampleCount, let sample = probe.lastSample {
                driftSamples.append(sample)
            }
            closedSampleCount = closed
        }

        /// Clears the probe and the sample log at the start of a scenario.
        func resetProbe() {
            probe.reset()
            driftSamples = []
            closedSampleCount = 0
        }

        // MARK: - Geometry

        /// Feeds the probe: the visible set, top-most first, then the tracked
        /// row's offset. The Mac gate's `reportGeometry`, for the flipped
        /// collection view.
        func reportGeometry() {
            let geometry = controller.layout.geometry
            let bounds = controller.collectionView.bounds
            guard bounds.height > 0 else { return }

            // The flip draws higher row indices higher on screen, so the
            // top-most visible row is the last one in the range.
            let visibleRows = geometry.rows(intersectingMinY: bounds.minY, maxY: bounds.maxY)
            var ids: [EventID] = []
            for row in visibleRows.reversed() where controller.rows.indices.contains(row) {
                if let id = TimelineGateEvent.eventID(forRowId: controller.rows[row].uniqueId) {
                    ids.append(id)
                }
            }
            if ids != lastVisibleIDs {
                lastVisibleIDs = ids
                probe.reportVisible(ids, range: store.visibleRange(spanning: ids))
            }

            guard let tracked = probe.trackedID,
                  let offset = distanceFromViewportTop(ofRowId: String(tracked.rawValue))
            else { return }
            probe.reportOffset(offset, for: tracked)
        }

        /// Where a row's top edge sits below the viewport's top edge, in
        /// points, increasing downward.
        ///
        /// The collection view is flipped: the document origin (the newest
        /// end) draws at the bottom, so the viewport's top edge is
        /// `bounds.maxY` and a row's top edge is its `maxY`. The same quantity
        /// the Mac gate reads off its unflipped table.
        private func distanceFromViewportTop(ofRowId rowId: String) -> Double? {
            let geometry = controller.layout.geometry
            guard let row = controller.snapshot.indexOfItem(rowId),
                  let minY = geometry.minY(ofRow: row)
            else { return nil }
            return Double(controller.collectionView.bounds.maxY - (minY + geometry.heights[row]))
        }

        /// The container's own anchor row and its edge's distance from the
        /// viewport origin, read the way the drain captures it.
        func anchorEdge() -> (rowId: String, edge: CGFloat)? {
            guard let anchor = controller.currentScrollAnchor() else { return nil }
            return (anchor.rowId, anchor.originBefore - controller.originY)
        }

        func edge(ofRowId rowId: String) -> CGFloat? {
            guard let row = controller.snapshot.indexOfItem(rowId),
                  let minY = controller.layout.geometry.minY(ofRow: row)
            else { return nil }
            return minY - controller.originY
        }

        // MARK: - Scrolling

        var maximumOriginY: CGFloat {
            max(0, controller.layout.geometry.contentHeight - controller.collectionView.bounds.height)
        }

        func scroll(toOriginY originY: CGFloat) {
            let clamped = min(max(0, originY), maximumOriginY)
            controller.collectionView.contentOffset = CGPoint(x: 0, y: clamped)
        }

        /// Fraction 0 is the newest end, 1 the oldest.
        func seek(toFraction fraction: CGFloat) async {
            scroll(toOriginY: maximumOriginY * fraction)
            await frames(10)
        }

        /// A steady drag toward the oldest end, positioned from the display
        /// link's own callbacks rather than a timer: MATRIX-65 found a
        /// wall-clock sleep racing the vsync it is measured against.
        func sweep(seconds: TimeInterval) async {
            let start = CACurrentMediaTime()
            let origin = controller.originY
            frameAction = { [weak self] in
                self?.scroll(toOriginY: origin + TimelineGatePlan.pointsPerSecond * CGFloat(CACurrentMediaTime() - start))
            }
            while CACurrentMediaTime() - start < seconds {
                await nextFrame()
            }
            frameAction = nil
        }

        // MARK: - Layout passes

        /// Resizes the viewport and runs the layout pass it causes, timed. A
        /// width change re-measures every row synchronously: heights are
        /// cached per width.
        func layoutPass(to size: CGSize) -> TimelineGateMeasurements.LayoutPass {
            let collectionView = controller.collectionView
            let fromWidth = collectionView.bounds.width
            let missesBefore = controller.heightCache.stats.misses
            let started = CACurrentMediaTime()
            container.frame.size = size
            collectionView.frame = container.bounds
            collectionView.layoutIfNeeded()
            let seconds = CACurrentMediaTime() - started
            let remeasured = controller.heightCache.stats.misses - missesBefore
            return TimelineGateMeasurements.LayoutPass(
                fromWidth: Double(fromWidth),
                toWidth: Double(size.width),
                rows: controller.rows.count,
                remeasured: remeasured,
                milliseconds: seconds * 1000,
                microsecondsPerRemeasure: remeasured > 0 ? seconds * 1_000_000 / Double(remeasured) : 0
            )
        }

        struct Quiescence {
            /// Frames the wait took.
            var frames = 0
            /// The worst content-queue length seen at a frame.
            var backlog = 0
            /// False when the wait hit `TimelineGatePlan.quiesceFrameCap`.
            var drained = false
        }

        /// Waits until the container took every recorded change and drained
        /// its content queue.
        func quiesce() async -> Quiescence {
            var wait = Quiescence()
            while wait.frames < TimelineGatePlan.quiesceFrameCap {
                if !feed.hasPendingChanges, controller.pendingRowUpdates.isEmpty, controller.rowUpdateDisplayLink == nil {
                    wait.drained = true
                    return wait
                }
                await nextFrame()
                wait.frames += 1
                wait.backlog = max(wait.backlog, controller.pendingRowUpdates.count)
            }
            return wait
        }

        /// Lets the open sample close on the probe's settle window, then
        /// holds the next one open again.
        func settleProbe() async {
            settlesProbe = true
            while probe.hasPendingSample {
                await nextFrame()
            }
            settlesProbe = false
        }
    }

    /// Counts the layout's `prepare()` passes (MATRIX-87).
    ///
    /// Stands between `TimelineStackLayout` and the controller, which the
    /// layout asks for every row height once per pass. A pass walks the whole
    /// timeline, so a plain scroll must never cause one.
    @MainActor
    final class TimelineGateLayoutProbe: TimelineStackLayoutHeightSource {
        weak var source: TimelineStackLayoutHeightSource?
        private(set) var passes = 0

        func rowHeights(forWidth width: CGFloat) -> [CGFloat] {
            passes += 1
            return source?.rowHeights(forWidth: width) ?? []
        }
    }
#endif

import AppKit
import Models
import SwiftUI
import TimelineSpikeCore

/// The M1 production timeline container, measured by the spike harness.
///
/// Unlike the S-13 and S-14 candidates, nothing in the measured path is spike
/// code. `TimelineViewController` and its two extensions are the app's own
/// files, compiled from symlinks in `Sources/ProductionTimeline/Production`,
/// so a change to the container changes what this renderer measures on the
/// next build. That is what makes the harness a gate rather than a museum.
///
/// The bridge supplies the container with what the app supplies it with: a
/// display-ordered item array and a queue of `TimelineDisplayChange`s. The
/// synthetic events reach it through `Models.EventTimelineItem`, so no SDK
/// type is required anywhere in the harness.
public struct ProductionTimelineRenderer: TimelineRenderer {
    public nonisolated static let rendererID = "m1-production"
    public nonisolated static let displayName = "M1 Production Container"
    public nonisolated static let summary =
        "The shipping TimelineViewController, its height cache and its scroll-anchor compensation, driven by synthetic events."

    private let harness: SpikeHarness

    public init(harness: SpikeHarness) {
        self.harness = harness
    }

    public var body: some View {
        ProductionTimelineRepresentable(
            harness: harness,
            revision: StoreRevision(store: harness.store)
        )
    }
}

/// What the representable watches.
///
/// `NSViewControllerRepresentable` has no `body`, so it cannot register with
/// Observation itself. Building this token in `ProductionTimelineRenderer.body`
/// reads the store's observable properties there, which is what brings SwiftUI
/// back here on every mutation tick and every prepend. No throttle, no
/// coalescing: every store change reaches the container.
struct StoreRevision: Equatable {
    let storeID: ObjectIdentifier
    let itemCount: Int
    let oldestIndex: Int
    let mutationCount: Int
    let prependedEventCount: Int

    @MainActor
    init(store: TimelineStore) {
        self.storeID = ObjectIdentifier(store)
        self.itemCount = store.items.count
        self.oldestIndex = store.oldestIndex
        self.mutationCount = store.appliedMutationCount
        self.prependedEventCount = store.prependedEventCount
    }
}

struct ProductionTimelineRepresentable: NSViewControllerRepresentable {
    let harness: SpikeHarness
    let revision: StoreRevision

    func makeCoordinator() -> ProductionTimelineCoordinator {
        ProductionTimelineCoordinator(harness: harness)
    }

    func makeNSViewController(context: Context) -> TimelineViewController {
        let controller = TimelineViewController(
            coordinator: TimelineViewRepresentable.Coordinator(
                appState: context.coordinator.appState,
                windowState: context.coordinator.windowState
            ),
            timeline: context.coordinator.bridge
        )
        context.coordinator.attach(to: controller)
        return controller
    }

    func updateNSViewController(_ controller: TimelineViewController, context: Context) {
        context.coordinator.applyStoreChanges(to: controller)
    }
}

/// Owns the bridge and the geometry reporting.
///
/// Reporting sits here rather than in the container because the container has
/// no idea the harness exists — keeping the probe out of the production files
/// is the whole point.
@MainActor
final class ProductionTimelineCoordinator {
    let appState = AppState()
    let windowState = WindowState()
    let bridge: LiveTimeline

    private let harness: SpikeHarness
    private weak var controller: TimelineViewController?
    private var lastReportedVisibleRange: NSRange?
    private var didAttachDisplayLink = false

    init(harness: SpikeHarness) {
        self.harness = harness
        self.bridge = LiveTimeline(harness: harness)
    }

    func attach(to controller: TimelineViewController) {
        self.controller = controller

        let clipView = controller.scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
    }

    /// Brings the display order level with the store, hands the batch to the
    /// container, and re-reads the geometry.
    func applyStoreChanges(to controller: TimelineViewController) {
        if !didAttachDisplayLink {
            didAttachDisplayLink = true
            harness.attachDisplayLink(to: controller.scrollView)
        }

        bridge.syncFromStore()
        controller.applyPendingTimelineChanges()
        reportGeometry()
    }

    @objc private func clipViewBoundsDidChange(_: Notification) {
        reportGeometry()
    }

    // MARK: - Geometry reporting

    /// Feeds the probe. Visible set first, because reporting it can retarget
    /// the tracked event, and the offset must belong to whichever event is
    /// tracked after that.
    private func reportGeometry() {
        guard let controller else { return }
        let probe = harness.probe
        let tableView = controller.tableView
        let visible = tableView.rows(in: tableView.visibleRect)
        let rows = controller.timelineRows

        if visible.length <= 0 {
            if lastReportedVisibleRange != nil {
                lastReportedVisibleRange = nil
                probe.reportVisible([], range: nil)
            }
        } else if visible != lastReportedVisibleRange {
            lastReportedVisibleRange = visible
            reportVisibleRows(visible, rows: rows, probe: probe)
        }

        // The offset goes out on every geometry change, not only when the
        // visible set moves: a height change above the tracked row moves it
        // without changing which rows are on screen, and that is the drift the
        // probe exists to catch.
        guard let tracked = probe.trackedID,
              let row = rows.firstIndex(where: { $0.uniqueId == String(tracked.rawValue) })
        else { return }
        probe.reportOffset(Double(distanceFromViewportTop(ofRow: row, in: controller)), for: tracked)
    }

    private func reportVisibleRows(_ visible: NSRange, rows: [Models.TimelineRow], probe: AnchorProbe) {
        let upper = visible.location + visible.length
        var ids: [EventID] = []
        ids.reserveCapacity(visible.length)
        for row in visible.location ..< upper where rows.indices.contains(row) {
            guard let id = SyntheticEventAdapter.eventID(forRowId: rows[row].uniqueId) else { continue }
            ids.append(id)
        }
        probe.reportVisible(ids, range: harness.store.visibleRange(spanning: ids))
    }

    /// Where a row's top edge sits below the top of the viewport, in points.
    ///
    /// The production table is **not** flipped and its rows run newest-first,
    /// so `y` grows upward from the newest end and a row's visual top edge is
    /// its `maxY`. The AppKit candidate's table is flipped and oldest-first, so
    /// its equivalent read is `minY - originY`. Both produce the same on-screen
    /// quantity, which is what makes the two sets of drift numbers comparable.
    private func distanceFromViewportTop(ofRow row: Int, in controller: TimelineViewController) -> CGFloat {
        let clipView = controller.scrollView.contentView
        let rowRect = controller.tableView.rect(ofRow: row)
        return clipView.bounds.origin.y + clipView.bounds.height - rowRect.maxY
    }
}

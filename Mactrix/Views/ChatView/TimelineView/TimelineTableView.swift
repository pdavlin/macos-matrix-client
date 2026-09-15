import AppKit
import MatrixRustSDK
import Models
import OSLog
import QuartzCore
import SwiftUI
import Tokens
import UI
import Utils

struct TimelineItemRowView: View {
    let row: TimelineRow
    let timeline: LiveTimeline?

    let appState: AppState
    let windowState: WindowState

    @AppStorage(TypographyToken.fontSizeStorageKey) private var fontSize = TypographyToken.defaultBaseFontSize

    init(row: TimelineRow, timeline: LiveTimeline?, coordinator: TimelineViewRepresentable.Coordinator) {
        self.row = row
        self.timeline = timeline
        self.appState = coordinator.appState
        self.windowState = coordinator.windowState
    }

    /// D-3: read receipts render in direct rooms only. A group room's receipt
    /// pile churns on every member's read and tells the reader nothing.
    private var showsReadReceipts: Bool {
        timeline?.room.roomInfo?.isDirect == true
    }

    @ViewBuilder
    var contentView: some View {
        switch row {
        case let .message(_, event, _, _):
            if let event = event as? MatrixRustSDK.EventTimelineItem, case let .msgLike(content: content) = event.content {
                ChatMessageView(timeline: timeline, event: event, msg: content, includeProfileHeader: true)
            } else {
                logAndShow("Message", log: "Message row did not resolve to an SDK event with msg-like content")
            }
        case let .state(_, event, name):
            if let event = event as? MatrixRustSDK.EventTimelineItem {
                UI.GenericEventView(event: event, name: name)
            } else {
                logAndShow(name, log: "State row did not resolve to an SDK event")
            }
        case let .virtual(_, item):
            UI.VirtualItemView(item: item)
        case let .typingIndicator(_, names):
            UI.TypingIndicatorRow(names: names)
        case .paginationActivity:
            UI.PaginationActivityRow()
        case let .paginationFailure(_, message):
            UI.PaginationFailureRow(message: message) {
                timeline?.retryPagination()
            }
        case .unsupported:
            // Height is clamped to 1pt by the measurement layer, so an
            // unrenderable item occupies a row without showing anything.
            EmptyView()
        }
    }

    private func logAndShow(_ text: String, log message: String) -> some View {
        Logger.timelineRowMapping.warning("\(message, privacy: .public)")
        return Text(text)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                contentView
                    .environment(appState)
                    .environment(windowState)
            }
        }
        .environment(\.timelineTypography, TimelineTypography(base: CGFloat(fontSize)))
        .environment(\.timelineShowsReadReceipts, showsReadReceipts)
    }
}

class TimelineViewController: NSViewController {
    let coordinator: TimelineViewRepresentable.Coordinator

    // Internal, not private: the diff-driven update path lives in
    // TimelineTableUpdates.swift and private is file-scoped.
    var dataSource: NSTableViewDiffableDataSource<TimelineSection, TimelineUniqueId>?
    /// The snapshot the table is showing, mutated in place per change.
    ///
    /// Kept as state rather than rebuilt per update: rebuilding meant
    /// appending every row again on every keystroke in a busy room, which is
    /// the O(timeline) cost S-34 removes.
    var snapshot = TimelineViewController.emptySnapshot()

    /// An empty snapshot with the sections already present, so an append
    /// never has to create one. Section order fixes row order: the typing
    /// section renders first and the table is unflipped, so it sits at the
    /// newest (bottom) end; pagination renders last, at the oldest end.
    static func emptySnapshot() -> NSDiffableDataSourceSnapshot<TimelineSection, TimelineUniqueId> {
        var snapshot = NSDiffableDataSourceSnapshot<TimelineSection, TimelineUniqueId>()
        snapshot.appendSections([.typingIndicator, .main, .paginationActivity])
        return snapshot
    }

    let scrollView = NSScrollView()
    let tableView = BottomStickyTableView()

    let timeline: LiveTimeline

    /// Every row the table shows, newest first: the typing indicator (when
    /// someone is typing), then the SDK item rows, then the pagination
    /// activity row (while a back-pagination is in flight).
    ///
    /// One array, one index space. Heights, the height cache, and the scroll
    /// anchor all address rows through it.
    var timelineRows: [TimelineRow] = []

    /// Number of decoration rows at the newest end. Item index `i` lives at
    /// table index `i + leadingDecorationCount`.
    var leadingDecorationCount = 0
    /// Number of decoration rows at the oldest end.
    var trailingDecorationCount = 0

    var itemRowCount: Int {
        timelineRows.count - leadingDecorationCount - trailingDecorationCount
    }

    /// Row heights keyed by (row id, width, token set), invalidated by
    /// content revision (S-32). `heightOfRow` consults this; misses measure
    /// offscreen via `measurementHostingView`.
    var heightCache = TimelineRowHeightCache<TimelineTypography>()
    /// Per-row content revision; bumped when the SDK replaces a row's content
    /// (a `.set` diff, arriving as `.update`).
    var rowRevisions: [String: Int] = [:]
    /// The token set heights are currently measured against.
    private var activeTypography: TimelineTypography

    init(coordinator: TimelineViewRepresentable.Coordinator, timeline: LiveTimeline) {
        self.coordinator = coordinator
        self.timeline = timeline
        self.activeTypography = Self.storedTypography()
        super.init(nibName: nil, bundle: nil)

        // Start from the current display order and take ownership of the
        // change queue, so the first update applies only what happens next.
        timelineRows = timeline.displayItems.map(\.row)
        _ = timeline.drainDisplayChanges()
        refreshDecorationRows(applyingSnapshot: false)
    }

    /// The typography token set as persisted by the appearance settings.
    ///
    /// Reads the same storage key the row views read through `@AppStorage`,
    /// so cache keys and rendered rows agree on the active token set.
    static func storedTypography() -> TimelineTypography {
        let stored = UserDefaults.standard.object(forKey: TypographyToken.fontSizeStorageKey) as? Int
        return TimelineTypography(base: CGFloat(stored ?? TypographyToken.defaultBaseFontSize))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.addTableColumn(NSTableColumn())
        tableView.headerView = nil
        tableView.style = .plain
        tableView.allowsColumnSelection = false
        tableView.selectionHighlightStyle = .none

        // S-32: manual `heightOfRow` + the height cache is the decided
        // mechanism (contract 2026-08-20). AppKit self-sizing stays off.
        tableView.usesAutomaticRowHeights = false

        oldWidth = tableView.tableColumns.first?.width

        dataSource = .init(tableView: tableView) { [weak self] tableView, _, row, _ in
            guard let self, timelineRows.indices.contains(row) else { return NSView() }

            let providerStarted = TimelineStormProfiler.enabled ? CACurrentMediaTime() : 0
            defer {
                if TimelineStormProfiler.enabled {
                    TimelineStormProfiler.recordProvider((CACurrentMediaTime() - providerStarted) * 1000)
                }
            }

            let model = timelineRows[row]
            let view = TimelineItemRowView(row: model, timeline: timeline, coordinator: coordinator)

            let hostView: NSHostingView<TimelineItemRowView>
            if let recycledView = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(model.reuseId), owner: self)
                as? NSHostingView<TimelineItemRowView>
            {
                if TimelineStormProfiler.enabled { TimelineStormProfiler.recordRecycled() }
                recycledView.rootView = view
                hostView = recycledView
            } else {
                hostView = NSHostingView<TimelineItemRowView>(rootView: view)
                hostView.identifier = NSUserInterfaceItemIdentifier(model.reuseId)
                // Heights are manual (S-32: heightOfRow + cache), so the in-table
                // hosting view must fill the frame the table assigns and must not
                // install intrinsic-size constraints. Self-sizing here fought the
                // manual frame and recursed through
                // _informContainerThatSubviewsNeedUpdateConstraints until AppKit
                // threw during layout on a content change (MATRIX-50). Only the
                // offscreen measurementHostingView self-sizes.
                hostView.translatesAutoresizingMaskIntoConstraints = true
                hostView.autoresizingMask = [.width, .height]
                hostView.sizingOptions = []
            }

            return hostView
        }

        tableView.delegate = self

        tableView.onLiveResizeEnd = { [weak self] in
            guard let self else { return }
            Logger.timelineTableView.debug("live resize ended: re-measuring all rows at the final width")
            noteAllRowHeightsChanged()
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true

        scrollView.automaticallyAdjustsContentInsets = false

        scrollView.drawsBackground = false
        tableView.backgroundColor = .clear
        view = scrollView

        // Subscribe to view resize notifications
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTableResize),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(viewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        // Token changes (font size in appearance settings) change measured
        // heights; the cache keys on the token set, so a change only needs a
        // re-note to trigger re-measurement.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUserDefaultsChange),
            name: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )

        rebuildSnapshot()

        listenForFocusTimelineItem()
        listenForScrollToBottomRequests()
        listenForTypingUsers()
        listenForPaginationActivity()
    }

    var heightRenoteScheduled = false
    /// Identifies the pending re-note, so a later width change retires it.
    private var heightRenoteGeneration = 0

    @objc func handleTableResize(_: Notification) {
        // Heights are cached against the column width, so that is the width a
        // re-measure must react to. The table frame can move without it.
        let width = tableView.tableColumns.first?.width
        guard oldWidth != width else { return }
        oldWidth = width
        scheduleHeightRenote()
    }

    /// How long a width must hold still before the rows are re-measured.
    ///
    /// AppKit settles a width in phases: the clip view takes the new width,
    /// then the scroll view tiles and the scroller's inset narrows the column
    /// one pass later. A SwiftUI width animation (the inspector transition)
    /// delivers a change per frame. Every phase used to buy its own full-table
    /// re-note — 150ms to 860ms, depending on how many rows the table has
    /// already measured — for a width that never finished rendering (S-59).
    private static let heightRenoteSettleDelay: TimeInterval = 0.1

    /// Re-measures the rows once the width stops moving, off the layout pass.
    ///
    /// The notification fires synchronously while the frame is being set, so
    /// re-noting here would run inside the current layout pass. A SwiftUI-driven
    /// frame animation (the inspector transition) queries the representable's
    /// size mid-pass, and invalidating row heights during that resolution
    /// dirties constraints while they are being resolved — AppKit turns that
    /// into a crash (the MATRIX-50 constraint-loop class). Deferring runs the
    /// re-note after the pass completes, breaking the re-entrancy.
    ///
    /// A live resize keeps the next-cycle timing: the drag must stay responsive,
    /// and it re-measures the visible rows only.
    private func scheduleHeightRenote() {
        heightRenoteScheduled = true
        heightRenoteGeneration &+= 1
        let generation = heightRenoteGeneration
        let delay = tableView.inLiveResize ? 0 : Self.heightRenoteSettleDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, generation == heightRenoteGeneration else { return }
            heightRenoteScheduled = false
            if tableView.inLiveResize {
                // During a live resize, re-measure only the visible rows for
                // responsiveness; `onLiveResizeEnd` settles the rest once.
                noteVisibleRowHeightsChanged()
            } else {
                noteAllRowHeightsChanged()
            }
        }
    }

    @objc func handleUserDefaultsChange(_: Notification) {
        let typography = Self.storedTypography()
        guard typography != activeTypography else { return }
        activeTypography = typography
        Logger.timelineTableView.info("typography tokens changed: re-measuring all rows")
        noteAllRowHeightsChanged()
    }

    var timelineFetchTask: Task<Void, Never>?

    /// Distance (in points) from the newest end within which the timeline
    /// still counts as scrolled to the bottom.
    static let bottomThreshold: CGFloat = 40.0

    /// Scroll-anchor state. The behaviour lives in `TimelineScrollAnchor`;
    /// the storage stays here because an extension cannot hold it.
    ///
    /// True while a compensation is writing the bounds origin.
    var isAdjustingScrollAnchor = false
    var scrollReportScheduled = false

    /// A focus request whose row has not arrived yet.
    ///
    /// Opening a room at an event (a notification, a reply jump, and the M3
    /// search jump) sets the focus before the SDK delivers the item, so the
    /// first attempt usually finds no row. The request is held here and retried
    /// after each timeline update instead of being dropped.
    var pendingFocusEventId: MatrixRustSDK.EventOrTransactionId?
    private var focusScrollScheduled = false

    /// Retries the pending focus scroll off the current runloop cycle.
    ///
    /// Callers run inside SwiftUI's view update pass; scrolling reports a new
    /// position, and that report writes observable timeline state (S-54).
    func scheduleFocusScroll() {
        guard pendingFocusEventId != nil, !focusScrollScheduled else { return }
        focusScrollScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            focusScrollScheduled = false
            scrollToPendingFocusIfPossible()
        }
    }

    func listenForFocusTimelineItem() {
        Logger.timelineTableView.debug("Listen for focus timeline item")

        let focusedTimelineEventId = withObservationTracking {
            timeline.focusedTimelineEventId
        } onChange: { [weak self] in
            Task { @MainActor in self?.listenForFocusTimelineItem() }
        }

        guard let focusedTimelineEventId else { return }
        pendingFocusEventId = focusedTimelineEventId
        scrollToPendingFocusIfPossible()
    }

    /// Scrolls to the focused row once it exists, and clears the request.
    ///
    /// A no-op while the row is absent, so it is safe to call after every
    /// update.
    func scrollToPendingFocusIfPossible() {
        guard let pendingFocusEventId else { return }
        // One pass, not two: the item index is the table index shifted by the
        // newest-end decorations, the same mapping the diff path applies. The
        // second scan this replaces re-found the row by identifier (MATRIX-58).
        guard let itemIndex = timeline.displayItems.firstIndex(where: { item in
            item.asEvent()?.eventOrTransactionId == pendingFocusEventId
        }) else { return }
        let rowIndex = itemIndex + leadingDecorationCount
        guard timelineRows.indices.contains(rowIndex) else { return }

        self.pendingFocusEventId = nil
        Logger.timelineTableView.info("focus event resolved to row \(rowIndex): scrolling")
        tableView.animateRowToVisible(rowIndex)
    }

    /// The last scroll-to-bottom request this controller acted on. Requests
    /// are a monotonic counter on `LiveTimeline`; observing the counter
    /// instead of a flag keeps repeated taps working.
    private var handledScrollToBottomRequests: Int = 0

    func listenForScrollToBottomRequests() {
        let requests = withObservationTracking {
            timeline.scrollToBottomRequests
        } onChange: { [weak self] in
            Task { @MainActor in self?.listenForScrollToBottomRequests() }
        }

        guard requests > handledScrollToBottomRequests else { return }
        handledScrollToBottomRequests = requests

        // Row 0 is the newest message: rows are display-ordered newest-first
        // and the table is not flipped, so row 0 sits at the bottom.
        tableView.animateRowToVisible(0)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    enum TimelineSection {
        /// Rendered first, so it lands at the newest (bottom) end.
        case typingIndicator
        case main
        /// Rendered last, so it lands at the oldest (top) end.
        case paginationActivity
    }

    /// The column width rows were last measured against; a width change is
    /// judged against this, not against the table frame.
    var oldWidth: CGFloat?
    /// Offscreen measurement host, concretely typed.
    ///
    /// An `AnyView` root hands SwiftUI a fresh root type on every assignment,
    /// so the view graph is torn down and rebuilt once per measurement instead
    /// of diffed against the row measured before it. The concrete root keeps
    /// the graph across measurements, which is most of the per-row cost
    /// (MATRIX-57). Lazy because the root needs the coordinator.
    lazy var measurementHostingView: NSHostingController<TimelineItemRowView> = {
        let controller = NSHostingController(
            rootView: TimelineItemRowView(row: .unsupported(uniqueId: ""), timeline: timeline, coordinator: coordinator)
        )
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }()
}

extension TimelineViewController: NSTableViewDelegate {
    func selectionShouldChange(in _: NSTableView) -> Bool {
        return false
    }

    func tableView(_: NSTableView, shouldSelectRow _: Int) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard timelineRows.indices.contains(row) else { return 1 }
        let model = timelineRows[row]

        let targetWidth = tableView.tableColumns[0].width
        let revision = rowRevisions[model.uniqueId] ?? 0

        let height = heightCache.height(
            for: model,
            width: targetWidth,
            tokens: activeTypography,
            revision: revision
        ) { rowModel, measureWidth in
            Logger.timelineTableView.debug(
                "height cache miss: measuring row \(rowModel.uniqueId, privacy: .public) at width \(measureWidth)"
            )
            return measureRowHeight(rowModel, width: measureWidth)
        }

        let stats = heightCache.stats
        if stats.lookups.isMultiple(of: 500) {
            Logger.timelineTableView.info(
                "height cache: \(stats.hits) hits / \(stats.misses) misses over \(stats.lookups) lookups"
            )
        }

        return height
    }

    /// Measures one row offscreen at the given width — the measurement
    /// source behind the cache, called only on a miss.
    private func measureRowHeight(_ row: TimelineRow, width: CGFloat) -> CGFloat {
        let started = TimelineStormProfiler.enabled ? CACurrentMediaTime() : 0
        measurementHostingView.rootView = TimelineItemRowView(row: row, timeline: timeline, coordinator: coordinator)

        let proposedSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        let height = measurementHostingView.sizeThatFits(in: proposedSize).height
        if TimelineStormProfiler.enabled {
            TimelineStormProfiler.recordMeasure((CACurrentMediaTime() - started) * 1000)
        }
        return height
    }
}

// TEMPORARY (MATRIX-57): storm batch profiler. Removed before the story lands.
@MainActor
enum TimelineStormProfiler {
    static let enabled = ProcessInfo.processInfo.environment["MACTRIX_TIMELINE_PROFILE"] == "1"

    struct Sample {
        var updates: Int
        var mutatedRows: Int
        var visibleMutated: Int
        var reloadMs: Double
        var noteMs: Double
        var measureMs: Double
        var measureCount: Int
        var totalMs: Double
        var providerMs: Double
        var providerCount: Int
        var recycledCount: Int
    }

    private static var samples: [Sample] = []
    private static var batchMeasureMs: Double = 0
    private static var batchMeasureCount = 0
    /// Measure time booked while a note-height call was on the stack.
    private static var insideNote = false
    private static var measureMsInsideNote: Double = 0
    private static var batchProviderMs: Double = 0
    private static var batchProviderCount = 0
    private static var batchRecycledCount = 0

    static func beginBatch() {
        batchMeasureMs = 0
        batchMeasureCount = 0
        measureMsInsideNote = 0
        batchProviderMs = 0
        batchProviderCount = 0
        batchRecycledCount = 0
    }

    static func recordProvider(_ milliseconds: Double) {
        batchProviderMs += milliseconds
        batchProviderCount += 1
    }

    static func recordRecycled() {
        batchRecycledCount += 1
    }

    static func markNote(_ active: Bool) {
        insideNote = active
    }

    static func recordMeasure(_ milliseconds: Double) {
        batchMeasureMs += milliseconds
        batchMeasureCount += 1
        if insideNote { measureMsInsideNote += milliseconds }
    }

    static func endBatch(
        updates: Int,
        mutatedRows: Int,
        visibleMutated: Int,
        reloadMs: Double,
        noteMs: Double,
        totalMs: Double
    ) {
        samples.append(
            Sample(
                updates: updates,
                mutatedRows: mutatedRows,
                visibleMutated: visibleMutated,
                reloadMs: reloadMs,
                noteMs: noteMs,
                measureMs: batchMeasureMs,
                measureCount: batchMeasureCount,
                totalMs: totalMs,
                providerMs: batchProviderMs,
                providerCount: batchProviderCount,
                recycledCount: batchRecycledCount
            )
        )
        if samples.count.isMultiple(of: 100) { report() }
    }

    static func report() {
        guard !samples.isEmpty else { return }
        func percentile(_ values: [Double], _ fraction: Double) -> Double {
            let sorted = values.sorted()
            let index = min(sorted.count - 1, max(0, Int((Double(sorted.count) * fraction).rounded(.down))))
            return sorted[index]
        }
        let totals = samples.map(\.totalMs)
        let reloads = samples.map(\.reloadMs)
        let notes = samples.map(\.noteMs)
        let measures = samples.map(\.measureMs)
        let rows = samples.map { Double($0.mutatedRows) }
        let visible = samples.map { Double($0.visibleMutated) }
        let measureCounts = samples.map { Double($0.measureCount) }
        func line(_ name: String, _ values: [Double]) -> String {
            "  \(name): p50 " + String(format: "%.2f", percentile(values, 0.5))
                + "  p95 " + String(format: "%.2f", percentile(values, 0.95))
                + "  max " + String(format: "%.2f", values.max() ?? 0)
                + "  mean " + String(format: "%.2f", values.reduce(0, +) / Double(values.count))
        }
        print("[StormProfile] \(samples.count) batches")
        print(line("total ms", totals))
        print(line("reload ms", reloads))
        print(line("note ms", notes))
        print(line("measure ms", measures))
        print(line("mutated rows", rows))
        print(line("visible mutated", visible))
        print(line("measure count", measureCounts))
        print(line("provider ms", samples.map(\.providerMs)))
        print(line("provider count", samples.map { Double($0.providerCount) }))
        print(line("recycled count", samples.map { Double($0.recycledCount) }))
        print("  measure ms inside note (last batch): " + String(format: "%.2f", measureMsInsideNote))
    }

    static func reset() {
        samples.removeAll()
    }
}

class BottomStickyTableView: NSTableView {
    /// Called once when a window live resize finishes, so the controller can
    /// settle heights for rows that were offscreen during the resize.
    var onLiveResizeEnd: (() -> Void)?

    // By returning false, the table starts drawing from the bottom up
    override var isFlipped: Bool {
        return false
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        onLiveResizeEnd?()
    }
}

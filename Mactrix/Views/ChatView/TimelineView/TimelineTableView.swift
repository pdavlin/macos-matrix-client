import AppKit
import MatrixRustSDK
import Models
import OSLog
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

        oldWidth = tableView.frame.width

        dataSource = .init(tableView: tableView) { [weak self] tableView, _, row, _ in
            guard let self, timelineRows.indices.contains(row) else { return NSView() }

            let model = timelineRows[row]
            let view = TimelineItemRowView(row: model, timeline: timeline, coordinator: coordinator)

            let hostView: NSHostingView<TimelineItemRowView>
            if let recycledView = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(model.reuseId), owner: self)
                as? NSHostingView<TimelineItemRowView>
            {
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

    @objc func handleTableResize(_: Notification) {
        guard oldWidth != tableView.frame.width else { return }
        oldWidth = tableView.frame.width
        scheduleHeightRenote()
    }

    /// Coalesces a width-change height re-note onto the next runloop cycle.
    /// This notification fires synchronously while the frame is being set, so
    /// re-noting here runs inside the current layout pass. A SwiftUI-driven
    /// frame animation (the inspector transition) queries the representable's
    /// size mid-pass, and invalidating row heights during that resolution
    /// dirties constraints while they are being resolved — AppKit turns that
    /// into a crash (the MATRIX-50 constraint-loop class). Deferring runs the
    /// re-note after the pass completes, breaking the re-entrancy.
    private func scheduleHeightRenote() {
        guard !heightRenoteScheduled else { return }
        heightRenoteScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
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

    private func noteVisibleRowHeightsChanged() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false

            let visibleRows = tableView.rows(in: tableView.visibleRect)
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: visibleRows.lowerBound ..< visibleRows.upperBound))
        }
    }

    private func noteAllRowHeightsChanged() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false

            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0 ..< tableView.numberOfRows))
        }
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

    func listenForFocusTimelineItem() {
        Logger.timelineTableView.debug("Listen for focus timeline item")

        let focusedTimelineEventId = withObservationTracking {
            timeline.focusedTimelineEventId
        } onChange: { [weak self] in
            Task { @MainActor in self?.listenForFocusTimelineItem() }
        }

        guard let focusedTimelineEventId,
              let focusedItem = timeline.displayItems.first(where: {
                  $0.asEvent()?.eventOrTransactionId == focusedTimelineEventId
              }),
              let rowIndex = timelineRows.firstIndex(where: { $0.uniqueId == focusedItem.uniqueId().id })
        else { return }

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

    // values used to track width changes
    var oldWidth: CGFloat?
    let measurementHostingView = {
        let hostView = NSHostingController(rootView: AnyView(EmptyView()))
        hostView.sizingOptions = [.preferredContentSize]
        return hostView
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
        measurementHostingView.rootView = AnyView(TimelineItemRowView(row: row, timeline: timeline, coordinator: coordinator))

        let proposedSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        return measurementHostingView.sizeThatFits(in: proposedSize).height
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

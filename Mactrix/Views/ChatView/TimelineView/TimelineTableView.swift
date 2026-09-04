import AppKit
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import Tokens
import UI

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

    @ViewBuilder
    var contentView: some View {
        switch row {
        case let .message(_, event):
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
    }
}

class TimelineViewController: NSViewController {
    let coordinator: TimelineViewRepresentable.Coordinator

    private var dataSource: NSTableViewDiffableDataSource<TimelineSection, TimelineUniqueId>?

    let scrollView = NSScrollView()
    let tableView = BottomStickyTableView()

    let timeline: LiveTimeline
    var timelineItems: [TimelineItem]
    var timelineRows: [TimelineRow] = []

    /// Row heights keyed by (row id, width, token set), invalidated by
    /// content revision (S-32). `heightOfRow` consults this; misses measure
    /// offscreen via `measurementHostingView`.
    var heightCache = TimelineRowHeightCache<TimelineTypography>()
    /// Per-row content revision; bumped when the SDK hands a new item
    /// instance for the same unique ID.
    private var rowRevisions: [String: Int] = [:]
    /// Identity of the SDK item instance behind each row, the mutation signal
    /// that drives revision bumps.
    private var rowItemIdentities: [String: ObjectIdentifier] = [:]
    /// The token set heights are currently measured against.
    private var activeTypography: TimelineTypography

    init(coordinator: TimelineViewRepresentable.Coordinator, timeline: LiveTimeline, timelineItems: [TimelineItem]) {
        self.coordinator = coordinator
        self.timeline = timeline
        self.timelineItems = timelineItems
        self.activeTypography = Self.storedTypography()
        super.init(nibName: nil, bundle: nil)
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
            guard let self else { return NSView() }

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

        listenForFocusTimelineItem()
        listenForScrollToBottomRequests()
    }

    private var heightRenoteScheduled = false

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

    @objc func viewDidScroll(_: Notification) {
        let currentOffset = scrollView.contentView.bounds.origin.y
        let timelineHeight = scrollView.contentView.documentRect.height
        let viewHeight = scrollView.contentView.documentVisibleRect.height

        // The table is not flipped, so y = 0 is the newest (bottom) end.
        timeline.setAtBottom(currentOffset <= Self.bottomThreshold)

        let distanceFromTop = timelineHeight - viewHeight - currentOffset
        let threshold: CGFloat = 200.0 // Pixels from the top to trigger load

        if distanceFromTop <= threshold, timelineFetchTask == nil {
            Logger.timelineTableView.info("Fetching older messages (scroll near top)")
            timelineFetchTask = Task {
                do {
                    try await timeline.fetchOlderMessages()
                } catch {
                    Logger.timelineTableView.error("Failed to fetch older messages: \(error)")
                }

                timelineFetchTask = nil
            }
        }
    }

    func listenForFocusTimelineItem() {
        Logger.timelineTableView.debug("Listen for focus timeline item")

        let focusedTimelineEventId = withObservationTracking {
            timeline.focusedTimelineEventId
        } onChange: { [weak self] in
            Task { @MainActor in self?.listenForFocusTimelineItem() }
        }

        guard let focusedTimelineEventId,
              let focusedItem = timelineItems.first(where: {
                  $0.asEvent()?.eventOrTransactionId == focusedTimelineEventId
              }),
              let focusedRowId = focusedItem.row?.uniqueId,
              let rowIndex = timelineRows.firstIndex(where: { $0.uniqueId == focusedRowId })
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
        case main
        case typingIndicator
    }

    func updateTimelineItems(_ timelineItems: [TimelineItem]) {
        Logger.timelineTableView.info("update timeline items")

        let oldIds = timelineRows.map(\.uniqueId)
        self.timelineItems = timelineItems.reversed()

        var rows: [TimelineRow] = []
        var identities: [String: ObjectIdentifier] = [:]
        for item in self.timelineItems {
            guard let row = item.row else { continue }
            rows.append(row)
            identities[row.uniqueId] = ObjectIdentifier(item)
        }
        timelineRows = rows
        let newIds = timelineRows.map(\.uniqueId)

        let mutatedIds = applyRowIdentities(identities)

        // If the IDs haven't changed, reload all rows in place (content-only update: reactions, read receipts, etc.)
        // Reloads all rows rather than just visible ones to avoid stale content in NSTableView's prepared/cached views.
        // The reload does not re-ask heights; only rows whose content mutated get re-measured.
        //
        // The reload redraws a mutated row's SwiftUI content immediately, but noteHeightOfRows
        // grows the row frame under NSTableView's default implicit animation (MATRIX-49) — for
        // the animation's duration the taller content is clipped to the still-short frame. Zero
        // out the animation, as the width/typography re-note paths below already do, so content
        // and frame land in the same layout pass.
        if oldIds == newIds {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false

                tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0 ..< timelineRows.count),
                                     columnIndexes: IndexSet(integer: 0))
                noteHeightChanges(forMutatedIds: mutatedIds, context: "content-only update")
            }
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<TimelineSection, TimelineUniqueId>()
        snapshot.appendSections([.main])

        for item in timelineRows {
            snapshot.appendItems([.init(id: item.uniqueId)], toSection: .main)
        }

        dataSource?.apply(snapshot, animatingDifferences: false)

        // New rows are measured on demand by `heightOfRow`; rows that
        // survived the diff with mutated content still need new heights.
        noteHeightChanges(forMutatedIds: mutatedIds, context: "structural update")
    }

    /// Bumps the content revision of every row whose backing SDK item
    /// instance changed, and prunes cache state for rows that left the
    /// timeline.
    ///
    /// The data layer replaces a `TimelineItem` instance whenever the SDK
    /// hands new content for it (a `.set` diff), so instance identity is an
    /// O(1) mutation signal — the fingerprint idea from the S-14 spike,
    /// without duplicating content fields.
    private func applyRowIdentities(_ identities: [String: ObjectIdentifier]) -> Set<String> {
        var mutatedIds: Set<String> = []
        for (id, identity) in identities {
            if let previous = rowItemIdentities[id], previous != identity {
                mutatedIds.insert(id)
                rowRevisions[id, default: 0] += 1
            }
        }
        let currentIds = Set(identities.keys)
        rowItemIdentities = identities
        rowRevisions = rowRevisions.filter { currentIds.contains($0.key) }
        heightCache.retain(rowIds: currentIds)
        return mutatedIds
    }

    /// Asks the table to re-measure exactly the rows whose content mutated.
    private func noteHeightChanges(forMutatedIds mutatedIds: Set<String>, context: String) {
        guard !mutatedIds.isEmpty else {
            Logger.timelineTableView.debug("\(context, privacy: .public): no row content mutations, heights kept")
            return
        }
        let indexes = IndexSet(timelineRows.enumerated()
            .filter { mutatedIds.contains($0.element.uniqueId) }
            .map(\.offset))
        Logger.timelineTableView.debug(
            "\(context, privacy: .public): re-measuring \(indexes.count) mutated row(s) of \(self.timelineRows.count)"
        )
        tableView.noteHeightOfRows(withIndexesChanged: indexes)
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

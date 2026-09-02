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

    init(coordinator: TimelineViewRepresentable.Coordinator, timeline: LiveTimeline, timelineItems: [TimelineItem]) {
        self.coordinator = coordinator
        self.timeline = timeline
        self.timelineItems = timelineItems
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.addTableColumn(NSTableColumn())
        tableView.headerView = nil
        tableView.style = .plain
        tableView.allowsColumnSelection = false
        tableView.selectionHighlightStyle = .none

        tableView.rowHeight = -1
        tableView.usesAutomaticRowHeights = true

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
                hostView.autoresizingMask = [.width, .height]
                hostView.sizingOptions = [.preferredContentSize]
                hostView.setContentHuggingPriority(.required, for: .vertical)
            }

            return hostView
        }

        tableView.delegate = self

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

        listenForFocusTimelineItem()
    }

    @objc func handleTableResize(_: Notification) {
        if oldWidth != tableView.frame.width {
            oldWidth = tableView.frame.width

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false

                let visibleRect = tableView.visibleRect
                let visibleRows = tableView.rows(in: visibleRect)
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: visibleRows.lowerBound ..< visibleRows.upperBound))
            }
        }
    }

    var timelineFetchTask: Task<Void, Never>?

    @objc func viewDidScroll(_: Notification) {
        let currentOffset = scrollView.contentView.bounds.origin.y
        let timelineHeight = scrollView.contentView.documentRect.height
        let viewHeight = scrollView.contentView.documentVisibleRect.height

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

        let oldIds = self.timelineRows.map(\.uniqueId)
        self.timelineItems = timelineItems.reversed()
        self.timelineRows = self.timelineItems.compactMap(\.row)
        let newIds = self.timelineRows.map(\.uniqueId)

        // If the IDs haven't changed, reload all rows in place (content-only update: reactions, read receipts, etc.)
        // Reloads all rows rather than just visible ones to avoid stale content in NSTableView's prepared/cached views.
        if oldIds == newIds {
            tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0 ..< self.timelineRows.count),
                                 columnIndexes: IndexSet(integer: 0))
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<TimelineSection, TimelineUniqueId>()
        snapshot.appendSections([.main])

        for item in self.timelineRows {
            snapshot.appendItems([.init(id: item.uniqueId)], toSection: .main)
        }

        dataSource?.apply(snapshot, animatingDifferences: false)

        // Re-measure visible rows after hosting views settle
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: visibleRows.lowerBound ..< visibleRows.upperBound))
        }
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
        let model = timelineRows[row]

        measurementHostingView.rootView = AnyView(TimelineItemRowView(row: model, timeline: timeline, coordinator: coordinator))

        let targetWidth = tableView.tableColumns[0].width
        let proposedSize = CGSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)

        let size = measurementHostingView.sizeThatFits(in: proposedSize)
        // Avoid undefined-height rows which can cause NSTableView layout issues
        return max(size.height, 1)
    }
}

class BottomStickyTableView: NSTableView {
    // By returning false, the table starts drawing from the bottom up
    override var isFlipped: Bool {
        return false
    }
}

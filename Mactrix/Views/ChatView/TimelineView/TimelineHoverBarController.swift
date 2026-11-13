import AppKit
import MatrixRustSDK
import Models
import Observation
import SwiftUI
import Tokens
import UI

// The timeline spike compiles this file without Core (see spike/GATE.md).
#if canImport(Core)
    import Core
#endif

// MATRIX-145: the timeline controller's side of the floating hover bar. The
// views, the storage, and the drawing live in `TimelineHoverBar.swift`; the
// decisions live in `Models.TimelineHoverBarState`.

// MARK: - Controller

extension TimelineViewController {
    /// Starts the hover bar's sheet observation once the timeline is in a
    /// window. The only `viewDidAppear` work of the controller; the matching
    /// teardown runs in `viewWillDisappear` (`hoverBarWillDisappear()`).
    override func viewDidAppear() {
        super.viewDidAppear()
        hoverBarDidAppear()
    }

    /// Adds the floating bar and the pointer tracking. Call once, after the
    /// scroll view is the controller's view.
    func installHoverBar() {
        hoverBar.install(in: scrollView.contentView)
        hoverBar.imageLoader = coordinator.appState.matrixClient
        hoverBar.tracker.onMove = { [weak self] windowPoint in
            self?.hoverBarPointerMoved(toWindowPoint: windowPoint)
        }
        hoverBar.tracker.onExit = { [weak self] in
            guard let self else { return }
            hoverBar.isPointerInside = false
            applyHoverBarEvent(.pointerExited)
        }
        tableView.onLayout = { [weak self] in
            self?.hoverBarTableDidLayout()
        }
        #if canImport(Core)
            reactionPicker.onOpenChange = { [weak self] isOpen in
                self?.applyHoverBarEvent(isOpen ? .suppress(.reactionPicker) : .unsuppress(.reactionPicker))
                if !isOpen { self?.reevaluateHoverBarPointer() }
            }
        #endif
    }

    /// Starts the sheet observation for the window the timeline is in.
    func hoverBarDidAppear() {
        guard let window = unsafe view.window else { return }
        hoverBar.observeSheets(on: window) { [weak self] isOpen in
            self?.applyHoverBarEvent(isOpen ? .suppress(.sheet) : .unsuppress(.sheet))
            if !isOpen { self?.reevaluateHoverBarPointer() }
        }
    }

    /// Hides the bar and ends the sheet observation.
    func hoverBarWillDisappear() {
        hoverBar.stopObservingSheets()
        hoverBar.isPointerInside = false
        applyHoverBarEvent(.pointerExited)
        hoverBar.hideNow()
    }

    // MARK: Pointer

    /// The only work on every pointer move: two conversions, two compares,
    /// and `row(at:)`. The bar and the highlight change only when the row
    /// under the pointer changes.
    func hoverBarPointerMoved(toWindowPoint windowPoint: NSPoint) {
        let clipView = scrollView.contentView
        let clipPoint = clipView.convert(windowPoint, from: nil)
        // The timeline runs under the toolbar; the pointer over the toolbar
        // is not over a row.
        let openTop = clipView.bounds.maxY - scrollView.safeAreaInsets.top
        guard clipView.bounds.contains(clipPoint), clipPoint.y <= openTop else {
            hoverBar.isPointerInside = false
            applyHoverBarEvent(.pointerExited)
            return
        }
        hoverBar.isPointerInside = true

        let point = tableView.convert(clipPoint, from: clipView)
        if let bar = hoverBar.barFrameInTable, bar.contains(point) {
            applyHoverBarEvent(.pointerOverBar)
            return
        }

        let row = tableView.row(at: point)
        guard row != hoverBar.lastPointerRow else { return }
        hoverBar.lastPointerRow = row
        applyHoverBarEvent(.pointerOverRow(hoverBarRowId(atRow: row)))
    }

    /// Reports the pointer again where it is now: after a scroll stops, a
    /// sheet or the picker closes, or the rows move under it.
    func reevaluateHoverBarPointer() {
        guard hoverBar.isPointerInside, let window = unsafe view.window else { return }
        hoverBar.lastPointerRow = nil
        hoverBarPointerMoved(toWindowPoint: window.mouseLocationOutsideOfEventStream)
    }

    /// The identity of the message row at table row `row`, or nil for a
    /// row that takes no bar.
    private func hoverBarRowId(atRow row: Int) -> String? {
        guard timelineRows.indices.contains(row), case .message = timelineRows[row] else { return nil }
        return timelineRows[row].uniqueId
    }

    // MARK: Scroll

    /// Hides the bar while the timeline scrolls. Per scroll frame: a flag
    /// check and a timer move, and nothing while the pointer is outside.
    func hoverBarDidScroll() {
        guard hoverBar.isPointerInside || hoverBar.state.isScrolling else { return }
        if !hoverBar.state.isScrolling {
            applyHoverBarEvent(.scrollBegan)
        }
        hoverBar.scheduleScrollSettle { [weak self] in
            guard let self else { return }
            applyHoverBarEvent(.scrollEnded)
            reevaluateHoverBarPointer()
        }
    }

    // MARK: Layout

    /// Keeps the bar on its row when the table lays out: rows inserted,
    /// re-measured, or removed, or a new width. Nothing to do while no row
    /// is hovered. A row that did not move costs a lookup and a compare.
    func hoverBarTableDidLayout() {
        guard let rowId = hoverBar.state.shownRow else { return }
        guard let index = rowIndex(ofRowId: rowId) else {
            // The row left the table. Apply it after the layout pass, since
            // the highlight change sets row views.
            DispatchQueue.main.async { [weak self] in
                self?.applyHoverBarEvent(.rowRemoved(rowId))
                self?.reevaluateHoverBarPointer()
            }
            return
        }
        let cellRect = tableView.frameOfCell(atColumn: 0, row: index)
        guard cellRect != hoverBar.shownCellRect else { return }
        hoverBar.shownCellRect = cellRect
        if hoverBar.placedRowId == rowId {
            placeHoverBar(rowAt: index)
        }
        // The rows moved under a pointer that did not move.
        DispatchQueue.main.async { [weak self] in
            self?.reevaluateHoverBarPointer()
        }
    }

    // MARK: State to drawing

    /// Applies one event and redraws what it changed.
    func applyHoverBarEvent(_ event: TimelineHoverBarState<String>.Event) {
        switch event {
        case .pointerOverRow, .pointerOverBar:
            break
        case .pointerExited, .scrollBegan, .scrollEnded, .suppress, .unsuppress, .rowRemoved:
            hoverBar.lastPointerRow = nil
        }
        guard hoverBar.state.apply(event) else { return }
        hoverBarShownRowDidChange()
    }

    private func hoverBarShownRowDidChange() {
        let shown = hoverBar.state.shownRow
        if hoverBar.highlightedRowId != shown {
            let previous = hoverBar.highlightedRowId
            hoverBar.highlightedRowId = shown
            if let previous { refreshHoverHighlight(ofRowId: previous) }
            if let shown { refreshHoverHighlight(ofRowId: shown) }
        }

        guard let shown, let index = rowIndex(ofRowId: shown) else {
            hoverBar.shownCellRect = nil
            hoverBar.hide()
            return
        }
        hoverBar.shownCellRect = tableView.frameOfCell(atColumn: 0, row: index)
        showHoverBar(rowAt: index, offeringTarget: true)
    }

    /// Gives a row view on the screen its hover background. A row view the
    /// table builds later reads `highlightedRowId` in the row provider.
    private func refreshHoverHighlight(ofRowId rowId: String) {
        guard let index = rowIndex(ofRowId: rowId),
              let host = tableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? NSHostingView<TimelineItemRowView>
        else { return }
        let row = timelineRows[index]
        host.rootView = TimelineItemRowView(
            row: row,
            timeline: source.timeline(for: row),
            coordinator: coordinator,
            isHovered: rowId == hoverBar.highlightedRowId
        )
    }

    /// Fills the bar for the row at `index` and places it there.
    ///
    /// The items are read under observation: when the facts behind them
    /// change while the bar shows (the message is pinned, the recent emoji
    /// load), the bar fills again.
    ///
    /// - Parameter offeringTarget: Whether to make the row's message the
    ///   Edit menu's target, as hovering a row did before (MATRIX-108). True
    ///   when the bar moves to a new row.
    private func showHoverBar(rowAt index: Int, offeringTarget: Bool) {
        let rowId = timelineRows[index].uniqueId
        hoverBar.contentGeneration &+= 1
        let generation = hoverBar.contentGeneration

        let content = withObservationTracking {
            hoverBarContent(rowAt: index)
        } onChange: { [weak self] in
            Task { @MainActor in self?.hoverBarContentDidChange(generation: generation) }
        }

        guard let content else {
            hoverBar.hide()
            return
        }
        #if canImport(Core)
            if offeringTarget {
                // The hovered row's own room (MATRIX-142): in a merged chat,
                // the member timeline that holds the message.
                content.timeline.messageActionTarget.offer(content.target)
            }
        #endif
        guard !content.items.isEmpty else {
            // No buttons for this message: the row keeps its hover
            // background, and the bar hides.
            hoverBar.hide()
            return
        }
        hoverBar.show(
            rowId: rowId,
            targetKey: content.target.key,
            items: content.items,
            fontSize: activeTypography.base,
            perform: content.target.perform
        )
        placeHoverBar(rowAt: index)
    }

    /// Fills the bar again when the facts behind its items changed.
    private func hoverBarContentDidChange(generation: Int) {
        guard generation == hoverBar.contentGeneration,
              let shown = hoverBar.state.shownRow,
              let index = rowIndex(ofRowId: shown)
        else { return }
        showHoverBar(rowAt: index, offeringTarget: false)
    }

    /// Places the bar at the row at `index`.
    private func placeHoverBar(rowAt index: Int) {
        guard case let .message(_, _, _, fingerprint) = timelineRows[index] else {
            hoverBar.hide()
            return
        }
        let cellRect = tableView.frameOfCell(atColumn: 0, row: index)
        let frame = HoverActionBarGeometry.barFrame(
            barSize: hoverBar.barSize,
            rowRect: cellRect,
            bodyTopInset: HoverActionBarGeometry.bodyTopInset(for: fingerprint.grouping),
            in: HoverActionBarGeometry.Viewport(
                visibleRect: tableView.visibleRect,
                topObscuredHeight: scrollView.safeAreaInsets.top,
                isFlipped: tableView.isFlipped
            )
        )
        hoverBar.place(atTableFrame: frame, table: tableView)
    }

    /// The anchor of the reaction picker when the bar shows for the
    /// message `key`: the bar's picker button, in the table's coordinates.
    /// Nil when the bar does not show for that message.
    func hoverBarPickerAnchor(forMessageKey key: String, buttonsAfter: Int?) -> CGRect? {
        guard hoverBar.placedTargetKey == key, let bar = hoverBar.barFrameInTable else { return nil }
        return HoverActionBarGeometry.pickerAnchor(inBar: bar, buttonsAfter: buttonsAfter)
    }

    /// What the bar shows for one row: the row's message target, its hover
    /// items, and the room timeline the actions go to.
    private struct HoverBarContent {
        let target: MessageActionTarget
        let items: [MessageActionItem]
        let timeline: LiveTimeline
    }

    /// The bar's content for the row at `index`, or nil for a row without a
    /// message target. The target is built from the row itself, never read
    /// from the Edit menu's slot, so the bar acts on the hovered message and
    /// not on a focused or stale one. Its actions go to the row's own room
    /// timeline (`TimelineRowSource.timeline(for:)`, MATRIX-142).
    private func hoverBarContent(rowAt index: Int) -> HoverBarContent? {
        #if canImport(Core)
            let row = timelineRows[index]
            guard case let .message(_, event, _, _) = row,
                  let event = event as? MatrixRustSDK.EventTimelineItem,
                  case let .msgLike(content: msg) = event.content,
                  let rowTimeline = source.timeline(for: row)
            else { return nil }
            let actions = ChatMessageActions(
                timeline: rowTimeline,
                event: event,
                msg: msg,
                appState: coordinator.appState,
                windowState: coordinator.windowState
            )
            let target = actions.actionTarget
            return HoverBarContent(target: target, items: target.items(on: .hoverRow), timeline: rowTimeline)
        #else
            return nil
        #endif
    }
}

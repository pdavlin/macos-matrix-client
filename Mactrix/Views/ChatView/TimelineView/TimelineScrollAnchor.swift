import AppKit
import Models
import OSLog
import Utils

// The timeline spike compiles this file without Core (see spike/GATE.md).
#if canImport(Core)
    import Core
#endif

/// Scroll geometry for the timeline: row-height invalidation, the pagination
/// trigger, and the measured-delta compensation that holds visible content
/// still when a structural update changes the document around it (S-33).
extension TimelineViewController {
    /// Re-measures the rows the viewport shows, plus half a viewport of rows
    /// below it. Internal, not private: the width path that calls it lives in
    /// `TimelineTableView.swift`.
    ///
    /// A live resize holds its anchor at the top (MATRIX-197), so when the
    /// rows get shorter, rows come into view from below. The margin measures
    /// them before they show, not one frame later.
    func noteVisibleRowHeightsChanged() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false

            // Unflipped: lower y is the newer end, which is below on screen.
            var rect = tableView.visibleRect
            let margin = rect.height / 2
            rect.origin.y -= margin
            rect.size.height += margin
            let rows = tableView.rows(in: rect)
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: rows.lowerBound ..< rows.upperBound))
        }
    }

    /// Drops every cached row height, which costs one synchronous re-measure
    /// of the rows AppKit re-queries — 150ms at 10k rows on a cold table, and
    /// 860ms once the table has measured a working set (S-59). Call it once
    /// per settled width, never once per layout phase.
    func noteAllRowHeightsChanged() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false

            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0 ..< tableView.numberOfRows))
        }
    }

    @objc func viewDidScroll(_: Notification) {
        // S-33 moves the bounds origin itself to compensate a structural update.
        // That move is not the user scrolling, and reporting it mid-update would
        // write observable timeline state inside SwiftUI's view update pass;
        // `scheduleScrollReport` sends the report once the pass is over.
        guard !isAdjustingScrollAnchor else {
            // Not scrolling either: the sticky day pill (MATRIX-136) only
            // records the new origin, so it does not take the next bounds
            // change for a scroll.
            _ = stickyDayPill.originDidMove(to: scrollView.contentView.bounds.origin.y)
            return
        }
        updateScrollPosition()
        updateStickyDayPill()
        // MATRIX-145: the content moves under the pointer, so the hover bar
        // hides until the scroll stops.
        hoverBarDidScroll()
    }

    private func updateScrollPosition() {
        let currentOffset = scrollView.contentView.bounds.origin.y
        let timelineHeight = scrollView.contentView.documentRect.height
        let viewHeight = scrollView.contentView.documentVisibleRect.height

        // The table is not flipped, so y = 0 is the newest (bottom) end.
        source.setAtBottom(currentOffset <= Self.bottomThreshold)

        let distanceFromTop = timelineHeight - viewHeight - currentOffset
        let threshold: CGFloat = 200.0 // Pixels from the top to trigger load

        if distanceFromTop <= threshold, timelineFetchTask == nil {
            Logger.timelineTableView.info("Fetching older messages (scroll near top)")
            timelineFetchTask = Task {
                await source.paginateBackwards()
                timelineFetchTask = nil
            }
        }

        if source.reportsNewestVisibleRow {
            reportNewestVisibleRow()
        }
    }

    /// Reports the scroll position off the current pass.
    ///
    /// `updateTimelineItems` runs inside SwiftUI's view update, and
    /// `updateScrollPosition` writes observable timeline state and can start a
    /// pagination fetch. Both belong after the pass, for the S-54 reason.
    private func scheduleScrollReport() {
        guard !scrollReportScheduled else { return }
        scrollReportScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            scrollReportScheduled = false
            updateScrollPosition()
        }
    }

    /// The visible row a compensation holds still across a structural update
    /// or a live resize.
    struct ScrollAnchor {
        /// Row identity, not index: a structural update renumbers rows.
        let rowId: String
        /// The row's distance from the document origin, before the update.
        /// A structural update holds this one.
        let originBefore: CGFloat
        /// The row's top edge below the top of the viewport, before the
        /// update. A live resize holds this one (MATRIX-197): the viewport
        /// height changes with the window and the row wraps again, so only
        /// its top edge stays where the reader looks.
        let distanceFromViewportTop: CGFloat
    }

    /// What a live resize holds still (MATRIX-197).
    enum LiveResizeHold {
        /// At the newest end. The unflipped geometry pins the bottom by
        /// itself, through every width and height, so nothing moves.
        case bottom
        /// The top-most visible row, at its distance from the viewport top.
        case row(ScrollAnchor)
    }

    /// True from `viewWillStartLiveResize` to `viewDidEndLiveResize`.
    ///
    /// `inLiveResize` is the window's state; the hold is the controller's own
    /// record of the same span, which a hosted test can also drive.
    var isLiveResizing: Bool {
        liveResizeHold != nil || tableView.inLiveResize
    }

    /// Captures the top-most visible row and where it sits in the document.
    ///
    /// Rows are display-ordered newest-first and the table is not flipped, so
    /// the document origin is the newest end and the visually top-most row is
    /// the highest visible index — the row nearest the end a back-pagination
    /// batch is inserted at.
    ///
    /// Returns `nil` where compensation must not run:
    /// - At the newest end, which the unflipped geometry already pins. Moving
    ///   the origin there would unpin it and stop new messages arriving in view.
    /// - While a width re-note is pending or a live resize is running. That
    ///   path (S-54) is about to re-measure every row, so it owns the scroll
    ///   geometry until it has run; compensating against heights it is about to
    ///   replace would fight it.
    func currentScrollAnchor() -> ScrollAnchor? {
        guard !heightRenoteScheduled, !isLiveResizing else { return nil }
        return topVisibleRowAnchor()
    }

    /// The top-most visible row and where it sits, or `nil` at the newest end
    /// (or with no rows on screen).
    private func topVisibleRowAnchor() -> ScrollAnchor? {
        let clipView = scrollView.contentView
        guard clipView.bounds.origin.y > Self.bottomThreshold else { return nil }

        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.length > 0 else { return nil }

        let topRow = visibleRows.location + visibleRows.length - 1
        guard timelineRows.indices.contains(topRow) else { return nil }

        let rowRect = tableView.rect(ofRow: topRow)
        return ScrollAnchor(
            rowId: timelineRows[topRow].uniqueId,
            originBefore: rowRect.minY,
            distanceFromViewportTop: clipView.bounds.maxY - rowRect.maxY
        )
    }

    /// Moves the viewport by the distance the anchor row actually moved, so the
    /// content the user is reading stays where it is.
    ///
    /// The delta is measured from `rect(ofRow:)` either side of the update
    /// rather than predicted from an inserted-row count, so it is right for a
    /// batch that both prepends and appends, and for any row the table moved on
    /// its own. The heights behind those rects come from the S-32 cache.
    ///
    /// `tile()` must have run first: the move is clamped against the document
    /// height, and an untiled table still reports the old one.
    func restoreScrollAnchor(_ anchor: ScrollAnchor) {
        guard let row = timelineRows.firstIndex(where: { $0.uniqueId == anchor.rowId }) else { return }

        let clipView = scrollView.contentView
        let originAfter = tableView.rect(ofRow: row).minY
        guard originAfter != anchor.originBefore else { return }

        let originY = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: clipView.bounds.origin.y,
            anchorOriginBefore: anchor.originBefore,
            anchorOriginAfter: originAfter,
            maximumOriginY: ScrollAnchorMath.maximumOriginY(
                documentHeight: tableView.frame.height,
                viewportHeight: clipView.bounds.height
            )
        )
        guard originY != clipView.bounds.origin.y else { return }

        Logger.timelineTableView.debug(
            "scroll anchor: row moved \(originAfter - anchor.originBefore)pt, compensating viewport"
        )

        moveViewport(toOriginY: originY)
    }

    /// Writes a compensating bounds origin. The move is not the user
    /// scrolling, so `viewDidScroll` ignores it and the report waits for the
    /// end of the pass.
    private func moveViewport(toOriginY originY: CGFloat) {
        let clipView = scrollView.contentView
        isAdjustingScrollAnchor = true
        clipView.setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: originY))
        scrollView.reflectScrolledClipView(clipView)
        isAdjustingScrollAnchor = false

        scheduleScrollReport()
    }

    // MARK: - Live resize (MATRIX-197)

    /// Records what the resize holds still: the top-most visible row and its
    /// distance from the viewport top, or the bottom pin at the newest end.
    func liveResizeDidStart() {
        liveResizeHold = topVisibleRowAnchor().map(LiveResizeHold.row) ?? .bottom
    }

    /// Re-measures every row at the final width once, then puts the anchor
    /// row back in the same step, so the rows that were offscreen during the
    /// drag do not move the content when they take their new heights.
    func liveResizeDidEnd() {
        Logger.timelineTableView.debug("live resize ended: re-measuring all rows at the final width")
        cancelHeightRenote()
        noteAllRowHeightsChanged()
        holdLiveResizeAnchor()
        liveResizeHold = nil
    }

    /// Retires a pending re-note. The end of a live resize re-measures every
    /// row itself, so a re-note the last frame of the drag queued would only
    /// repeat that work.
    private func cancelHeightRenote() {
        heightRenoteGeneration &+= 1
        heightRenoteScheduled = false
    }

    /// Moves the viewport so the anchor row's top edge is back at its
    /// distance from the viewport top. Absolute, not a delta, so it is safe
    /// to call on every frame of the drag and again after each re-measure.
    /// A no-op outside a live resize and for the bottom pin.
    func holdLiveResizeAnchor() {
        // The snapshot's identity lookup, not a scan of the rows: this runs
        // on every frame of the drag.
        guard case let .row(anchor) = liveResizeHold, let row = rowIndex(ofRowId: anchor.rowId) else { return }

        let clipView = scrollView.contentView
        let viewportHeight = clipView.bounds.height
        let originY = ScrollAnchorMath.clamped(
            tableView.rect(ofRow: row).maxY + anchor.distanceFromViewportTop - viewportHeight,
            maximumOriginY: ScrollAnchorMath.maximumOriginY(
                documentHeight: tableView.frame.height,
                viewportHeight: viewportHeight
            )
        )
        guard originY != clipView.bounds.origin.y else { return }
        moveViewport(toOriginY: originY)
    }
}

// MARK: - Focus, scroll to bottom, and the newest visible row

/// The scrolls the source asks for: a focused event (a notification, a
/// reply jump, the M3 search jump) and the newest row. Moved here from
/// `TimelineTableView.swift` with MATRIX-142 Wave 2, when the controller
/// started to read them from its `TimelineRowSource`.
extension TimelineViewController {
    /// Retries the pending focus scroll off the current runloop cycle.
    ///
    /// Callers run inside SwiftUI's view update pass; scrolling reports a new
    /// position, and that report writes observable timeline state (S-54).
    func scheduleFocusScroll() {
        guard pendingFocus != nil, !focusScrollScheduled else { return }
        focusScrollScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            focusScrollScheduled = false
            scrollToPendingFocusIfPossible()
        }
    }

    func listenForFocusTimelineItem() {
        Logger.timelineTableView.debug("Listen for focus timeline item")

        let focusTarget = withObservationTracking {
            source.focusTarget
        } onChange: { [weak self] in
            Task { @MainActor in self?.listenForFocusTimelineItem() }
        }

        guard let focusTarget else { return }
        pendingFocus = focusTarget
        scrollToPendingFocusIfPossible()
    }

    /// Scrolls to the focused row once it exists, and clears the request.
    ///
    /// A no-op while the row is absent, so it is safe to call after every
    /// update.
    func scrollToPendingFocusIfPossible() {
        guard let pendingFocus, let rowIndex = rowIndex(of: pendingFocus) else { return }

        self.pendingFocus = nil
        Logger.timelineTableView.info("focus event resolved to row \(rowIndex): scrolling")
        // MATRIX-136: the row flashes when the scroll lands.
        scrollToFocusedRow(rowIndex)
    }

    /// The table row that shows an event, or nil while the table has no row
    /// for it.
    ///
    /// One pass over the source to find the row identifier, then the
    /// snapshot's identity lookup (`rowIndex(ofRowId:)`), which also confirms
    /// that the table already shows the row. The focus jump and the reaction
    /// picker (MATRIX-138) both use it.
    func rowIndex(of event: TimelineEventReference) -> Int? {
        source.rowId(of: event).flatMap(rowIndex(ofRowId:))
    }

    func listenForScrollToBottomRequests() {
        let requests = withObservationTracking {
            source.scrollToBottomRequests
        } onChange: { [weak self] in
            Task { @MainActor in self?.listenForScrollToBottomRequests() }
        }

        guard requests > handledScrollToBottomRequests else { return }
        handledScrollToBottomRequests = requests

        // Row 0 is the newest message: rows are display-ordered newest-first
        // and the table is not flipped, so row 0 sits at the bottom.
        tableView.animateRowToVisible(0)
    }

    /// Reports the newest visible row after the current pass, for a source
    /// that sends read receipts per visible row (MATRIX-142). A structural
    /// batch calls it, because new rows can move the newest visible row
    /// without a scroll. The report reaches observable state, so it waits
    /// for the end of the SwiftUI update (S-54).
    func scheduleNewestVisibleRowReport() {
        guard source.reportsNewestVisibleRow, !newestVisibleRowReportScheduled else { return }
        newestVisibleRowReportScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            newestVisibleRowReportScheduled = false
            reportNewestVisibleRow()
        }
    }

    /// Tells the source the newest visible row that is not a decoration.
    /// Only while the window is key: a read receipt says the user saw it.
    func reportNewestVisibleRow() {
        guard unsafe view.window?.isKeyWindow == true else { return }
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.length > 0 else { return }
        let newest = max(visible.location, leadingDecorationCount)
        let end = min(visible.location + visible.length, timelineRows.count - trailingDecorationCount)
        guard newest < end else { return }
        source.noteNewestVisibleRow(id: timelineRows[newest].uniqueId)
    }
}

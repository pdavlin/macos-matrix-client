import AppKit
import Models
import OSLog
import Utils

/// Scroll geometry for the timeline: the pagination trigger, and the
/// measured-delta compensation that holds visible content still when a
/// structural update changes the document around it (S-33).
extension TimelineViewController {
    @objc func viewDidScroll(_: Notification) {
        // S-33 moves the bounds origin itself to compensate a structural update.
        // That move is not the user scrolling, and reporting it mid-update would
        // write observable timeline state inside SwiftUI's view update pass;
        // `scheduleScrollReport` sends the report once the pass is over.
        guard !isAdjustingScrollAnchor else { return }
        updateScrollPosition()
    }

    private func updateScrollPosition() {
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

    /// The visible row a compensation holds still across a structural update.
    struct ScrollAnchor {
        /// Row identity, not index: a structural update renumbers rows.
        let rowId: String
        /// The row's distance from the document origin, before the update.
        let originBefore: CGFloat
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
        guard !heightRenoteScheduled, !tableView.inLiveResize else { return nil }
        guard scrollView.contentView.bounds.origin.y > Self.bottomThreshold else { return nil }

        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.length > 0 else { return nil }

        let topRow = visibleRows.location + visibleRows.length - 1
        guard timelineRows.indices.contains(topRow) else { return nil }

        return ScrollAnchor(
            rowId: timelineRows[topRow].uniqueId,
            originBefore: tableView.rect(ofRow: topRow).minY
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

        isAdjustingScrollAnchor = true
        clipView.setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: originY))
        scrollView.reflectScrolledClipView(clipView)
        isAdjustingScrollAnchor = false

        scheduleScrollReport()
    }
}

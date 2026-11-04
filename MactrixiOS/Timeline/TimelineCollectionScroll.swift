import Models
import OSLog
import UIKit
import Utils

/// The visible row a compensation holds still across an update.
struct ScrollAnchor {
    /// Row identity, not index: a structural update renumbers rows.
    let rowId: String
    /// The row's distance from the document origin before the update.
    let originBefore: CGFloat
}

/// Scroll geometry: the anchor compensation (S-33), the pagination trigger,
/// the at-bottom report, scroll-to-bottom, and focus requests.
extension TimelineCollectionController: UICollectionViewDelegate {
    /// The viewport's distance from the document origin (the newest end).
    var originY: CGFloat {
        collectionView.contentOffset.y
    }

    /// Captures the visible row farthest from the newest end.
    ///
    /// Nil at the newest end: the flipped geometry already pins it, and moving
    /// the offset there would stop new messages arriving in view. Nil also
    /// while the user drags: a finger owns the offset, and writing it under
    /// the finger is a visible jump.
    func currentScrollAnchor() -> ScrollAnchor? {
        guard !TimelineScrollMetrics.isAtBottom(originY: originY), !collectionView.isTracking else { return nil }
        let viewport = collectionView.bounds
        guard let row = layout.geometry.anchorRow(viewportMinY: viewport.minY, viewportMaxY: viewport.maxY),
              rows.indices.contains(row),
              let minY = layout.geometry.minY(ofRow: row)
        else { return nil }
        return ScrollAnchor(rowId: rows[row].uniqueId, originBefore: minY)
    }

    /// Moves the viewport by the distance the anchor row moved.
    ///
    /// The delta is measured from the layout's geometry either side of the
    /// update, never predicted from a row count. The layout must have run its
    /// `prepare()` for the new rows first.
    func restoreScrollAnchor(_ anchor: ScrollAnchor) {
        guard let row = snapshot.indexOfItem(anchor.rowId),
              let originAfter = layout.geometry.minY(ofRow: row),
              originAfter != anchor.originBefore
        else { return }

        let target = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: originY,
            anchorOriginBefore: anchor.originBefore,
            anchorOriginAfter: originAfter,
            maximumOriginY: ScrollAnchorMath.maximumOriginY(
                documentHeight: layout.geometry.contentHeight,
                viewportHeight: collectionView.bounds.height
            )
        )
        guard target != originY else { return }

        Logger.timelineIOS.debug("scroll anchor: row moved \(originAfter - anchor.originBefore)pt, compensating")
        isAdjustingScrollAnchor = true
        collectionView.contentOffset = CGPoint(x: collectionView.contentOffset.x, y: target)
        isAdjustingScrollAnchor = false
    }

    func scrollViewDidScroll(_: UIScrollView) {
        // A compensation is not the user scrolling; its report runs after.
        guard !isAdjustingScrollAnchor else { return }
        updateScrollPosition()
    }

    private func updateScrollPosition() {
        feed.setAtBottom(TimelineScrollMetrics.isAtBottom(originY: originY))

        guard collectionView.bounds.height > 0,
              TimelineScrollMetrics.shouldPaginate(
                  originY: originY,
                  documentHeight: layout.geometry.contentHeight,
                  viewportHeight: collectionView.bounds.height
              ),
              timelineFetchTask == nil
        else { return }

        Logger.timelineIOS.info("fetching older messages (scroll near the oldest end)")
        timelineFetchTask = Task { [weak self] in
            guard let feed = self?.feed else { return }
            await feed.fetchOlderMessages()
            self?.timelineFetchTask = nil
        }
    }

    /// Reports the scroll position after the current pass. A report writes
    /// observable state and can start a fetch, which must not run inside an
    /// update (the S-54 reason).
    func scheduleScrollReport() {
        guard !scrollReportScheduled else { return }
        scrollReportScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            scrollReportScheduled = false
            updateScrollPosition()
        }
    }

    // MARK: - Scroll to bottom

    /// Acts on new scroll-to-bottom requests. The feed counts requests, so
    /// repeated taps all land.
    func handleScrollToBottomRequests() {
        let requests = feed.scrollToBottomRequests
        guard requests > handledScrollToBottomRequests else { return }
        handledScrollToBottomRequests = requests
        // Row 0 is the newest message, at the document origin.
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: 0), animated: true)
    }

    // MARK: - Focus

    /// Takes a new focus request from the feed. The event usually arrives
    /// after the request, so it waits and retries after structural updates.
    func handleFocusRequest() {
        let requestId = feed.focusRequestId
        guard requestId != handledFocusRequestId else { return }
        handledFocusRequestId = requestId
        pendingFocus = requestId != nil
        schedulePendingFocusScroll()
    }

    func schedulePendingFocusScroll() {
        guard pendingFocus, !focusScrollScheduled else { return }
        focusScrollScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            focusScrollScheduled = false
            scrollToPendingFocusIfPossible()
        }
    }

    private func scrollToPendingFocusIfPossible() {
        guard pendingFocus, let itemIndex = feed.itemIndexOfFocusRequest() else { return }
        let row = itemIndex + leadingDecorationCount
        guard rows.indices.contains(row) else { return }
        pendingFocus = false
        Logger.timelineIOS.info("focus event resolved to row \(row): scrolling")
        collectionView.scrollToItem(at: IndexPath(item: row, section: 0), at: .centeredVertically, animated: true)
    }
}

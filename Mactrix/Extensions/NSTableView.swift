import AppKit

extension NSTableView {
    /// Animates scrolling to row with a given index.
    ///
    /// - Parameters:
    ///   - index: the row to show.
    ///   - completion: runs on the main actor once the row is in view: after
    ///     the scroll animation ends, or at once when the row is already fully
    ///     visible. It does not run for an index outside the table or for a
    ///     table outside a scroll view (MATRIX-136 flashes the row here).
    func animateRowToVisible(_ index: Int, completion: (@MainActor () -> Void)? = nil) {
        guard index >= 0, index < numberOfRows else { return }
        guard let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView

        guard let targetY = originYShowingRow(index) else {
            // Row is already fully visible: Exit
            completion?()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            var newBounds = clipView.bounds
            newBounds.origin.y = targetY
            clipView.animator().bounds = newBounds
        } completionHandler: {
            MainActor.assumeIsolated {
                completion?()
            }
        }
    }

    /// The clip view origin that brings a row into view, or nil when the row
    /// already shows in full (or there is no such row or scroll view).
    ///
    /// The row lands in the part of the clip view that its content insets do
    /// not cover: above the floating composer of the timeline (MATRIX-198).
    func originYShowingRow(_ index: Int) -> CGFloat? {
        guard index >= 0, index < numberOfRows, let scrollView = enclosingScrollView else { return nil }

        let rowRect = rect(ofRow: index)
        let clipView = scrollView.contentView
        let bounds = clipView.bounds
        // The insets at the low-y and the high-y edge of the bounds.
        let insets = clipView.contentInsets
        let lowInset = clipView.isFlipped ? insets.top : insets.bottom
        let highInset = clipView.isFlipped ? insets.bottom : insets.top

        if rowRect.minY < bounds.minY + lowInset {
            // The row is past the low-y edge: bring its low-y edge to that edge.
            return rowRect.minY - lowInset
        }
        if rowRect.maxY > bounds.maxY - highInset {
            // The row is past the high-y edge: bring its high-y edge to that edge.
            return rowRect.maxY - bounds.height + highInset
        }
        return nil
    }
}

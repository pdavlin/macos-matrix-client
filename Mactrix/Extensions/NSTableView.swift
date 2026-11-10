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

        let rowRect = rect(ofRow: index)
        let clipView = scrollView.contentView
        let visibleRect = clipView.bounds

        var targetY = visibleRect.origin.y
        if rowRect.origin.y < visibleRect.origin.y {
            // Row is above: Scroll up until the top of the row is at the top
            targetY = rowRect.origin.y
        } else if rowRect.maxY > visibleRect.maxY {
            // Row is below: Scroll down until the bottom of the row is at the bottom
            targetY = rowRect.maxY - visibleRect.height
        } else {
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
}

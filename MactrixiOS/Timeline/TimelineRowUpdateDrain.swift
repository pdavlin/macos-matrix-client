import Models
import OSLog
import QuartzCore
import UIKit

/// Spends a per-frame budget on queued content updates (MATRIX-57), the iOS
/// form of the Mac drain. The budget is a share of the frame the display link
/// paces (`TimelineDrainBudget`), so a ProMotion panel keeps the same share.
///
/// What a content update leaves of the budget goes to the rows a width change
/// left with placeholder heights (MATRIX-98).
extension TimelineCollectionController {
    /// True while content updates or width-change measures are owed.
    var hasDrainWork: Bool {
        !pendingRowUpdates.isEmpty || !widthRemeasureQueue.isEmpty
    }

    /// Starts the drain for whatever is queued. Never drains synchronously:
    /// callers run inside an update.
    func scheduleRowUpdateDrain() {
        guard hasDrainWork, rowUpdateDisplayLink == nil else { return }

        // No window: nothing is presented, so there is no frame to pace.
        guard collectionView.window != nil else {
            scheduleUnpacedRowUpdateDrain()
            return
        }

        // `.common` so the drain keeps running while the user scrolls.
        let link = CADisplayLink(target: self, selector: #selector(drainRowUpdatesForFrame(_:)))
        link.add(to: .main, forMode: .common)
        rowUpdateDisplayLink = link
    }

    private func scheduleUnpacedRowUpdateDrain() {
        guard !unpacedRowUpdateDrainScheduled else { return }
        unpacedRowUpdateDrainScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            unpacedRowUpdateDrainScheduled = false
            drainRowUpdates(budget: .infinity)
        }
    }

    /// Stops the per-frame callback. `CADisplayLink` retains its target, so
    /// the link is released the frame the queue empties.
    func stopRowUpdateDrain() {
        rowUpdateDisplayLink?.invalidate()
        rowUpdateDisplayLink = nil
    }

    @objc
    private func drainRowUpdatesForFrame(_ link: CADisplayLink) {
        drainRowUpdates(budget: TimelineDrainBudget.budget(forFrameInterval: link.targetTimestamp - link.timestamp))
    }

    /// Applies queued updates, visible rows first, until the budget is spent.
    ///
    /// Heights change as one step per frame: the anchor is captured before
    /// the first row, and the layout re-runs once after the last one, with
    /// the compensation in the same non-animated pass.
    private func drainRowUpdates(budget: CFTimeInterval) {
        guard hasDrainWork else {
            stopRowUpdateDrain()
            return
        }

        let started = CACurrentMediaTime()
        let anchor = currentScrollAnchor()
        let visible = Set(collectionView.indexPathsForVisibleItems.map(\.item))
        var visibleOwed = visibleOwedRows()

        var applied = 0
        var remeasured = 0
        var widthMeasured = 0
        var changedRows = IndexSet()
        var spent: CFTimeInterval = 0
        var lastRowCost: CFTimeInterval = 0

        // The first row always runs, so a drain always makes progress; after
        // that, the next row is charged what the last one cost.
        while spent + lastRowCost <= budget {
            let rowStarted = CACurrentMediaTime()
            let next = pendingRowUpdates.take(
                limit: 1,
                resolve: { [weak self] id in self?.rowIndex(ofRowId: id) },
                isVisible: { visible.contains($0) }
            )
            if let update = next.first {
                if applyRowUpdate(update, changedRows: &changedRows) { remeasured += 1 }
                applied += 1
            } else if let index = nextOwedRow(visibleOwed: &visibleOwed) {
                // Measured now, so the cost lands in this row's charge.
                measureOwedRow(at: index)
                changedRows.insert(index)
                widthMeasured += 1
            } else {
                break
            }
            let now = CACurrentMediaTime()
            lastRowCost = now - rowStarted
            spent = now - started
        }

        // Only the rows that changed are re-read: the layout re-sums offsets
        // from the first of them and keeps every other height.
        if !changedRows.isEmpty {
            UIView.performWithoutAnimation {
                layout.invalidateHeights(ofRows: changedRows)
                collectionView.layoutIfNeeded()
                if let anchor {
                    restoreScrollAnchor(anchor)
                }
            }
            scheduleScrollReport()
        }

        Logger.timelineIOS.debug(
            """
            row update drain: \(applied) applied, \(remeasured) re-measured, \(widthMeasured) width-measured, \
            \(self.pendingRowUpdates.count) left, \(self.widthPlaceholders.count) owed
            """
        )
        if !hasDrainWork {
            stopRowUpdateDrain()
        }
    }

    /// Swaps in one row's new content and redraws it, and reports whether
    /// its height can have changed.
    ///
    /// A height-neutral change (equal MATRIX-63 fingerprints) keeps the
    /// revision, so the cache keeps the measured height and the layout never
    /// asks again. The redraw always runs: a re-tallied pill still has to show
    /// its new count.
    private func applyRowUpdate(
        _ update: TimelineRowUpdateQueue<TimelineRow>.Resolved,
        changedRows: inout IndexSet
    ) -> Bool {
        let previous = rows[update.index]
        rows[update.index] = update.payload

        let heightIsUnchanged = TimelineRowHeightFingerprint.heightIsUnchanged(from: previous, to: update.payload)
        if !heightIsUnchanged {
            rowRevisions[update.uniqueId, default: 0] += 1
        }

        // The row and its newer neighbor can change their sender header.
        let regrouped = regroup((update.index - 1) ..< (update.index + 1))
        reconfigureVisibleCell(atRow: update.index)
        for row in regrouped where row != update.index {
            reconfigureVisibleCell(atRow: row)
        }
        if !heightIsUnchanged {
            changedRows.insert(update.index)
        }
        changedRows.formUnion(IndexSet(regrouped))
        return !heightIsUnchanged || !regrouped.isEmpty
    }

    /// Resolves a row identity to its current index through the snapshot,
    /// whose item order is `rows` order. The identity re-check is the
    /// invariant that makes writing a row through the index safe.
    private func rowIndex(ofRowId rowId: String) -> Int? {
        guard let index = snapshot.indexOfItem(rowId) else { return nil }
        guard rows.indices.contains(index), rows[index].uniqueId == rowId else {
            Logger.timelineIOS.error("row update drain: snapshot index \(index) does not name row \(rowId, privacy: .public)")
            return nil
        }
        return index
    }
}

import Models
import OSLog
import QuartzCore
import UIKit

/// Spends a per-frame budget on queued content updates (MATRIX-57), the iOS
/// form of the Mac drain. The budget is a share of the frame the display link
/// paces (`TimelineDrainBudget`), so a ProMotion panel keeps the same share.
extension TimelineCollectionController {
    /// Starts the drain for whatever is queued. Never drains synchronously:
    /// callers run inside an update.
    func scheduleRowUpdateDrain() {
        guard !pendingRowUpdates.isEmpty, rowUpdateDisplayLink == nil else { return }

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
        guard !pendingRowUpdates.isEmpty else {
            stopRowUpdateDrain()
            return
        }

        let started = CACurrentMediaTime()
        let anchor = currentScrollAnchor()
        let visible = Set(collectionView.indexPathsForVisibleItems.map(\.item))

        var applied = 0
        var remeasured = 0
        var spent: CFTimeInterval = 0
        var lastRowCost: CFTimeInterval = 0

        // The first row always runs, so a drain always makes progress; after
        // that, the next row is charged what the last one cost.
        while spent + lastRowCost <= budget {
            let next = pendingRowUpdates.take(
                limit: 1,
                resolve: { [weak self] id in self?.rowIndex(ofRowId: id) },
                isVisible: { visible.contains($0) }
            )
            guard let update = next.first else { break }

            let rowStarted = CACurrentMediaTime()
            if applyRowUpdate(update) { remeasured += 1 }
            let now = CACurrentMediaTime()
            lastRowCost = now - rowStarted
            spent = now - started
            applied += 1
        }

        if remeasured > 0 {
            UIView.performWithoutAnimation {
                layout.invalidateLayout()
                collectionView.layoutIfNeeded()
                if let anchor {
                    restoreScrollAnchor(anchor)
                }
            }
            scheduleScrollReport()
        }

        Logger.timelineIOS.debug(
            "row update drain: \(applied) applied, \(remeasured) re-measured, \(self.pendingRowUpdates.count) left"
        )
        if pendingRowUpdates.isEmpty {
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
    private func applyRowUpdate(_ update: TimelineRowUpdateQueue<TimelineRow>.Resolved) -> Bool {
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

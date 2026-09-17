import AppKit
import MatrixRustSDK
import Models
import OSLog
import QuartzCore

// MARK: - Frame-amortized content updates

/// Spends a per-frame budget on the queued content updates (MATRIX-57).
///
/// A storm tick mutates ~5 rows and costs ~11.6ms to redraw, all of it SwiftUI
/// text layout: the row reload rebuilds the visible views and the height note
/// measures the offscreen ones. Neither got cheaper — an in-place reconfigure
/// and a deferred measurement both measured worse — so the work is paced
/// instead. Nothing about the S-32 cache or its revision-based invalidation
/// changes here; only *when* the work runs does.
///
/// The per-frame budget is a share of the frame the link is pacing rather than
/// a flat 6ms (MATRIX-64). See `TimelineDrainBudget` for why the two are the
/// same thing at 60 Hz and not at 120 Hz.
extension TimelineViewController {
    /// Starts or resumes the drain for whatever is queued.
    ///
    /// Callers run inside SwiftUI's view update pass, so this never drains
    /// synchronously: applying row heights there is the S-54 re-entrancy.
    func scheduleRowUpdateDrain() {
        guard !pendingRowUpdates.isEmpty else { return }
        guard rowUpdateDisplayLink == nil else { return }

        // No window means nothing is being presented, so there is no frame to
        // pace against and no cost to paying the whole queue at once.
        guard view.window != nil else {
            scheduleUnpacedRowUpdateDrain()
            return
        }

        // A display link, not a chain of `DispatchQueue.main.async` hops: the
        // main queue drains inside one runloop turn, before the transaction
        // commits, so chained hops would run every drain in the same frame and
        // pace nothing. `.common` mode because S3 is a storm *while scrolling*,
        // and `.default` alone stalls during scroll tracking.
        let link = view.displayLink(target: self, selector: #selector(drainRowUpdatesForFrame(_:)))
        link.add(to: .main, forMode: .common)
        rowUpdateDisplayLink = link
    }

    /// Applies everything queued on the next runloop cycle, without pacing.
    ///
    /// Only reachable before the view has a window. The flag stops a burst of
    /// updates queueing one hop each.
    private func scheduleUnpacedRowUpdateDrain() {
        guard !unpacedRowUpdateDrainScheduled else { return }
        unpacedRowUpdateDrainScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            unpacedRowUpdateDrainScheduled = false
            drainRowUpdates(budget: .infinity)
        }
    }

    /// Stops the per-frame callback and releases the controller back.
    ///
    /// `CADisplayLink` retains its target, so the link is invalidated the frame
    /// the queue empties rather than held for the controller's lifetime. The
    /// retain that a running drain holds is bounded by the queue: no new work
    /// arrives once the room is gone, so the last chunk releases the controller.
    private func stopRowUpdateDrain() {
        rowUpdateDisplayLink?.invalidate()
        rowUpdateDisplayLink = nil
    }

    /// Spends a share of *this* frame, not a fixed number of milliseconds.
    ///
    /// The link reports the interval it is pacing, so the budget follows the
    /// display: a third of a frame at 60 Hz, a third of a frame at 120 Hz. A
    /// flat budget would take 72% of a ProMotion frame and leave the SwiftUI
    /// update, the table's layout and the compositor the remainder. Capacity is
    /// unaffected — see `TimelineDrainBudget`, where the interval cancels.
    @objc
    private func drainRowUpdatesForFrame(_ link: CADisplayLink) {
        let frameInterval = link.targetTimestamp - link.timestamp
        drainRowUpdates(budget: TimelineDrainBudget.budget(forFrameInterval: frameInterval))
    }

    /// Applies queued updates, visible rows first, until the budget is spent.
    private func drainRowUpdates(budget: CFTimeInterval) {
        guard !pendingRowUpdates.isEmpty else {
            stopRowUpdateDrain()
            return
        }
        // A compensation is writing the bounds origin. Changing row heights
        // underneath it would move the content the S-33 restore is measuring
        // against; the next frame's drain picks the work up unchanged.
        guard !isAdjustingScrollAnchor else { return }

        let started = CACurrentMediaTime()
        TimelineStormProfiler.beginDrain()

        var applied = 0
        var visibleApplied = 0
        var skippedMeasures = 0
        var reloadMs = 0.0
        var noteMs = 0.0

        // A row is applied whole: the reload and the note are single calls and
        // SwiftUI lays a row out in one pass, so the budget cannot interrupt
        // one. It can only decide whether to start another, which it does by
        // charging the next row what the last one cost. That keeps the spend
        // inside the budget without a fixed per-row estimate to go stale, and
        // the first row always runs, so a drain always makes progress.
        var spent: CFTimeInterval = 0
        var lastRowCost: CFTimeInterval = 0

        // Zero duration for the MATRIX-49 reason: a re-noted row must not be
        // clipped to its old frame while an implicit row animation runs.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false

            while spent + lastRowCost <= budget {
                let visible = tableView.rows(in: tableView.visibleRect)
                let next = pendingRowUpdates.take(
                    limit: 1,
                    resolve: { [weak self] id in self?.rowIndex(ofRowId: id) },
                    isVisible: { $0 >= visible.location && $0 < visible.location + visible.length }
                )
                guard let update = next.first else { break }

                let rowStarted = CACurrentMediaTime()
                let timing = applyRowUpdate(update)
                let now = CACurrentMediaTime()
                lastRowCost = now - rowStarted
                spent = now - started

                applied += 1
                if update.isVisible { visibleApplied += 1 }
                if timing.skippedMeasure { skippedMeasures += 1 }
                reloadMs += timing.reloadMs
                noteMs += timing.noteMs
            }
        }

        let remaining = pendingRowUpdates.count
        if remaining == 0 {
            Logger.timelineTableView.debug("row update drain: queue empty after \(applied) row(s)")
            stopRowUpdateDrain()
        }

        TimelineStormProfiler.endDrain(
            .init(
                rows: applied,
                visibleRows: visibleApplied,
                skippedMeasures: skippedMeasures,
                reloadMs: reloadMs,
                noteMs: noteMs,
                totalMs: TimelineStormProfiler.elapsedMilliseconds(since: started),
                remaining: remaining
            )
        )
    }

    /// Swaps in one row's new content, redraws exactly that row, and re-measures
    /// it only if its height can have changed.
    ///
    /// The revision bump is what invalidates the S-32 height cache entry, so it
    /// must land before the note asks for the height. A height-neutral mutation
    /// gets neither (MATRIX-63): the row keeps its revision, so the cache keeps
    /// answering with the height it already measured, and the note — which is
    /// what drives the offscreen SwiftUI measure — never runs.
    ///
    /// The reload always runs. Skipping the measure is not skipping the update:
    /// a re-tallied reaction pill has to redraw its count, it just does not have
    /// to be measured again to do it.
    private func applyRowUpdate(
        _ update: TimelineRowUpdateQueue<TimelineRow>.Resolved
    ) -> RowUpdateTiming {
        // Read before the swap: this is the content the cached height was
        // measured against.
        let previous = timelineRows[update.index]
        timelineRows[update.index] = update.payload

        let heightIsUnchanged = TimelineRowHeightFingerprint.heightIsUnchanged(
            from: previous,
            to: update.payload
        )
        if !heightIsUnchanged {
            rowRevisions[update.uniqueId, default: 0] += 1
        }
        let rows = IndexSet(integer: update.index)

        // `NSTableView` caches prepared views, so a content change that does not
        // move rows still needs an explicit reload to show. The note is what
        // forces a height question; if the reload asks one of its own, the
        // answer is the same, because an unchanged revision is a cache hit.
        let reloadStarted = TimelineStormProfiler.now()
        tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
        let noteStarted = TimelineStormProfiler.now()
        if !heightIsUnchanged {
            tableView.noteHeightOfRows(withIndexesChanged: rows)
        }
        let finished = TimelineStormProfiler.now()

        return RowUpdateTiming(
            reloadMs: TimelineStormProfiler.milliseconds(from: reloadStarted, to: noteStarted),
            noteMs: TimelineStormProfiler.milliseconds(from: noteStarted, to: finished),
            skippedMeasure: heightIsUnchanged
        )
    }

    /// What applying one row cost, and whether it took the measurement path.
    private struct RowUpdateTiming {
        var reloadMs: Double
        var noteMs: Double
        var skippedMeasure: Bool
    }

    /// Resolves a row identity to the index it currently occupies.
    ///
    /// The snapshot is the id-to-index map the container already maintains, and
    /// its item order is `timelineRows`' order: sections are appended typing,
    /// main, pagination, which is how the rows array is laid out. The identity
    /// re-check is not defensive dressing — it is the invariant that makes an
    /// O(1) lookup safe to write a row through.
    private func rowIndex(ofRowId rowId: String) -> Int? {
        guard let index = snapshot.indexOfItem(TimelineUniqueId(id: rowId)) else { return nil }
        guard timelineRows.indices.contains(index), timelineRows[index].uniqueId == rowId else {
            Logger.timelineTableView.error(
                "row update drain: snapshot index \(index) does not name row \(rowId, privacy: .public)"
            )
            return nil
        }
        return index
    }
}

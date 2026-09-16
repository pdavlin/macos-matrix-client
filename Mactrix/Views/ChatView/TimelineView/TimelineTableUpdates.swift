import AppKit
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI

// MARK: - Diff-driven updates

extension TimelineViewController {
    /// Applies everything the timeline changed since the last view update.
    ///
    /// Cost is proportional to the diff, not to the timeline: the display
    /// order is maintained by `LiveTimeline` (no per-update reversed copy),
    /// and row identity comes from the diff (no full identifier rescan).
    ///
    /// Structural changes apply here and now — they are rare, and the S-33
    /// anchor compensation needs the whole batch to be one atomic visual step.
    /// Content-only updates are queued instead: a storm tick mutates more rows
    /// than one frame can redraw, so the drain spends a frame budget on them
    /// (MATRIX-57). This method never redraws a row itself.
    func applyPendingTimelineChanges() {
        let updates = timeline.drainDisplayChanges()
        guard !updates.isEmpty else { return }

        let profileStarted = TimelineStormProfiler.now()
        TimelineStormProfiler.beginBatch()

        // Captured against the old rows and the old geometry, before either is
        // replaced. Only a structural batch consumes it.
        let isStructural = updates.contains { $0.change.isStructural }
        let anchor = isStructural ? currentScrollAnchor() : nil

        var touchedRows = 0
        var queuedRows = 0
        var didReset = false

        for update in updates {
            touchedRows += update.change.rowCount
            switch update.change {
            case .reset:
                applyReset()
                didReset = true
            case let .insert(index, count):
                applyInsert(at: index, count: count, items: update.items)
            case let .remove(index, count):
                applyRemove(at: index, count: count)
            case let .update(index):
                if enqueueUpdate(at: index, item: update.items.first) { queuedRows += 1 }
            }
        }

        Logger.timelineTableView.info(
            """
            timeline update: \(updates.count) change(s) touching \(touchedRows) row(s) \
            of \(self.timelineRows.count) (structural: \(isStructural), reset: \(didReset)), \
            \(self.pendingRowUpdates.count) row(s) queued for the drain
            """
        )

        // The apply and the compensating scroll are one visual step, so the
        // intermediate geometry must not be presented. A zero duration also
        // keeps the clamp in `restoreScrollAnchor` reading the settled document
        // height rather than an animating one (MATRIX-49). A content-only batch
        // moves nothing, so it skips the transaction entirely.
        var applyMs = 0.0

        if isStructural {
            let applyStarted = TimelineStormProfiler.now()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false

                dataSource?.apply(snapshot, animatingDifferences: false)

                guard let anchor else { return }
                tableView.tile()
                restoreScrollAnchor(anchor)
            }
            applyMs = TimelineStormProfiler.elapsedMilliseconds(since: applyStarted)
        }

        scheduleRowUpdateDrain()

        TimelineStormProfiler.endBatch(
            .init(
                updates: updates.count,
                queuedRows: queuedRows,
                structuralRows: isStructural ? touchedRows - queuedRows : 0,
                applyMs: applyMs,
                totalMs: TimelineStormProfiler.elapsedMilliseconds(since: profileStarted)
            )
        )

        // A focus request usually lands before its event does, so the row it
        // names may have arrived in this batch. Only a structural batch can
        // deliver a row that was absent, so a content-only batch never retries:
        // an unresolved request would otherwise pay a scan of the whole
        // timeline on every edit that arrives (MATRIX-58). Deferred, not called
        // here: this method runs inside SwiftUI's view update pass and
        // scrolling reports a new position, which writes observable timeline
        // state — the S-54 re-entrancy.
        if isStructural {
            scheduleFocusScroll()
        }
    }

    private func applyReset() {
        timelineRows = timeline.displayItems.map(\.row)
        heightCache.invalidateAll()
        rowRevisions.removeAll()
        // Every row is rebuilt from the source of truth, which already carries
        // the content the queue was holding.
        pendingRowUpdates.removeAll()
        leadingDecorationCount = 0
        trailingDecorationCount = 0
        refreshDecorationRows(applyingSnapshot: false)
        rebuildSnapshot()
    }

    private func applyInsert(at index: Int, count: Int, items: [TimelineItem]) {
        guard items.count == count,
              TimelineDisplayOrder.isValidInsertIndex(index, count: itemRowCount)
        else {
            applyReset()
            return
        }

        let tableIndex = index + leadingDecorationCount
        // Resolved before the splice: after it, this position holds a new row.
        let beforeId = tableIndex < timelineRows.count - trailingDecorationCount
            ? timelineRows[tableIndex].uniqueId
            : nil

        let rows = items.map(\.row)
        timelineRows.insert(contentsOf: rows, at: tableIndex)

        let ids = rows.map { TimelineUniqueId(id: $0.uniqueId) }
        if let beforeId, snapshot.indexOfItem(TimelineUniqueId(id: beforeId)) != nil {
            snapshot.insertItems(ids, beforeItem: TimelineUniqueId(id: beforeId))
        } else {
            snapshot.appendItems(ids, toSection: .main)
        }
    }

    private func applyRemove(at index: Int, count: Int) {
        guard count > 0, index >= 0, index + count <= itemRowCount else {
            applyReset()
            return
        }

        let tableIndex = index + leadingDecorationCount
        let removed = timelineRows[tableIndex ..< (tableIndex + count)]
        let removedIds = removed.map(\.uniqueId)
        timelineRows.removeSubrange(tableIndex ..< (tableIndex + count))

        for id in removedIds {
            heightCache.invalidate(rowId: id)
            rowRevisions[id] = nil
        }
        // The drain drops an identity it cannot resolve, but the same identity
        // can be re-inserted by a later resync; a returning row must not
        // inherit the payload queued against the copy that left.
        pendingRowUpdates.remove(uniqueIds: removedIds)
        deleteSnapshotItems(withIds: removedIds)
    }

    /// Queues one row's new content for the drain, and reports whether it was
    /// queued.
    ///
    /// The identity check stays here rather than moving to the drain: a
    /// replacement that also changes identity is structural, and deferring it
    /// would leave the snapshot naming a row the timeline no longer has.
    private func enqueueUpdate(at index: Int, item: TimelineItem?) -> Bool {
        guard let item, TimelineDisplayOrder.isValidIndex(index, count: itemRowCount) else {
            applyReset()
            return false
        }

        let tableIndex = index + leadingDecorationCount
        let row = item.row

        guard row.uniqueId == timelineRows[tableIndex].uniqueId else {
            applyReset()
            return false
        }

        pendingRowUpdates.enqueue(uniqueId: row.uniqueId, payload: row)
        return true
    }

    /// Deletes snapshot items, ignoring identifiers the snapshot no longer
    /// holds. A reset earlier in the same batch can already have dropped them.
    private func deleteSnapshotItems(withIds ids: [String]) {
        let present = ids
            .map { TimelineUniqueId(id: $0) }
            .filter { snapshot.indexOfItem($0) != nil }
        guard !present.isEmpty else { return }
        snapshot.deleteItems(present)
    }

    /// Rebuilds the whole snapshot. Only a reset and the initial load take
    /// this path; every other update mutates the snapshot in place.
    func rebuildSnapshot() {
        var fresh = Self.emptySnapshot()

        let leading = timelineRows.prefix(leadingDecorationCount)
        let trailing = timelineRows.suffix(trailingDecorationCount)
        let items = timelineRows.dropFirst(leadingDecorationCount).dropLast(trailingDecorationCount)

        fresh.appendItems(leading.map { TimelineUniqueId(id: $0.uniqueId) }, toSection: .typingIndicator)
        fresh.appendItems(items.map { TimelineUniqueId(id: $0.uniqueId) }, toSection: .main)
        fresh.appendItems(trailing.map { TimelineUniqueId(id: $0.uniqueId) }, toSection: .paginationActivity)

        snapshot = fresh
        dataSource?.apply(snapshot, animatingDifferences: false)
    }
}

// MARK: - Decoration rows

extension TimelineViewController {
    /// Identity of the pagination row. Stable: its content never changes.
    private static let paginationRowId = "mactrix.timeline.paginationActivity"
    /// Identity prefix of the pagination failure row; the message completes it.
    private static let paginationFailureRowId = "mactrix.timeline.paginationFailure"

    /// Watches who is typing and keeps the newest-end decoration in step (D-3).
    func listenForTypingUsers() {
        let userIds = withObservationTracking {
            timeline.room.typingUserIds
        } onChange: { [weak self] in
            Task { @MainActor in self?.listenForTypingUsers() }
        }

        Logger.timelineTableView.debug("typing indicator: \(userIds.count) user(s) typing")
        refreshDecorationRows(applyingSnapshot: true)
    }

    /// Watches back-pagination and keeps the oldest-end decoration in step (D-2).
    ///
    /// Infinite scroll stays, so this row is the only signal that a fetch is
    /// running — or that one failed — at the oldest end. Both properties are
    /// read inside the tracking closure so either change re-arms the watch.
    func listenForPaginationActivity() {
        let (status, failure) = withObservationTracking {
            (timeline.paginating, timeline.paginationFailure)
        } onChange: { [weak self] in
            Task { @MainActor in self?.listenForPaginationActivity() }
        }

        Logger.timelineTableView.debug(
            "pagination status: \(status.debugDescription, privacy: .public) failure: \(failure ?? "none", privacy: .public)"
        )
        refreshDecorationRows(applyingSnapshot: true)
    }

    /// Display names of the users currently typing, resolved against the
    /// member list and falling back to the raw user ID.
    private var typingNames: [String] {
        let members = timeline.room.members
        return timeline.room.typingUserIds.map { userId in
            members.first { $0.userId == userId }?.displayName ?? userId
        }
    }

    private var wantsTypingRow: Bool {
        !timeline.room.typingUserIds.isEmpty
    }

    /// The oldest-end decoration for the current state, or nil for neither.
    ///
    /// A failure outranks activity: after a failed fetch nothing is in flight,
    /// so showing the spinner would promise a batch that is not coming. Row
    /// identity carries the message, so a different failure replaces the row
    /// rather than reusing a height measured for the previous text.
    private var wantsPaginationRow: TimelineRow? {
        if let failure = timeline.paginationFailure {
            return .paginationFailure(uniqueId: "\(Self.paginationFailureRowId):\(failure)", message: failure)
        }
        if case .paginating = timeline.paginating {
            return .paginationActivity(uniqueId: Self.paginationRowId)
        }
        return nil
    }

    /// Adds, removes, or re-labels the decoration rows to match current state.
    ///
    /// The typing row's identity carries the names it shows, so a change of
    /// who is typing is a delete plus an insert. That keeps the height cache
    /// honest: a stable identity with changing content would return the height
    /// measured for the previous label.
    func refreshDecorationRows(applyingSnapshot: Bool) {
        let typingRow: TimelineRow? = wantsTypingRow
            ? .typingIndicator(uniqueId: "mactrix.timeline.typing:\(typingNames.joined(separator: "|"))", names: typingNames)
            : nil
        let paginationRow = wantsPaginationRow

        let currentTyping = leadingDecorationCount > 0 ? timelineRows.first : nil
        let currentPagination = trailingDecorationCount > 0 ? timelineRows.last : nil

        let typingChanged = currentTyping?.uniqueId != typingRow?.uniqueId
        let paginationChanged = currentPagination?.uniqueId != paginationRow?.uniqueId
        guard typingChanged || paginationChanged else { return }

        if typingChanged {
            if let currentTyping {
                timelineRows.removeFirst()
                leadingDecorationCount = 0
                heightCache.invalidate(rowId: currentTyping.uniqueId)
                deleteSnapshotItems(withIds: [currentTyping.uniqueId])
            }
            if let typingRow {
                timelineRows.insert(typingRow, at: 0)
                leadingDecorationCount = 1
                snapshot.appendItems([TimelineUniqueId(id: typingRow.uniqueId)], toSection: .typingIndicator)
            }
        }

        if paginationChanged {
            if let currentPagination {
                timelineRows.removeLast()
                trailingDecorationCount = 0
                heightCache.invalidate(rowId: currentPagination.uniqueId)
                deleteSnapshotItems(withIds: [currentPagination.uniqueId])
            }
            if let paginationRow {
                timelineRows.append(paginationRow)
                trailingDecorationCount = 1
                snapshot.appendItems([TimelineUniqueId(id: paginationRow.uniqueId)], toSection: .paginationActivity)
            }
        }

        guard applyingSnapshot else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            dataSource?.apply(snapshot, animatingDifferences: false)
        }
    }
}

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
    /// row identity comes from the diff (no full identifier rescan), and a
    /// content-only change reloads the rows it names instead of all of them.
    func applyPendingTimelineChanges() {
        let updates = timeline.drainDisplayChanges()
        guard !updates.isEmpty else { return }

        // Captured against the old rows and the old geometry, before either is
        // replaced. Only a structural batch consumes it.
        let isStructural = updates.contains { $0.change.isStructural }
        let anchor = isStructural ? currentScrollAnchor() : nil

        // Table indices of rows whose content changed. A structural change
        // later in the same batch shifts them, so they are moved rather than
        // rediscovered: rescanning every row for the mutated identifiers is
        // the O(timeline) cost this story removes.
        var mutatedIndices: Set<Int> = []
        var touchedRows = 0
        var didReset = false

        for update in updates {
            touchedRows += update.change.rowCount
            switch update.change {
            case .reset:
                applyReset()
                didReset = true
                mutatedIndices.removeAll()
            case let .insert(index, count):
                if let tableIndex = applyInsert(at: index, count: count, items: update.items) {
                    mutatedIndices = Self.shift(mutatedIndices, insertedAt: tableIndex, count: count)
                } else {
                    mutatedIndices.removeAll()
                }
            case let .remove(index, count):
                if let tableIndex = applyRemove(at: index, count: count) {
                    mutatedIndices = Self.shift(mutatedIndices, removedAt: tableIndex, count: count)
                } else {
                    mutatedIndices.removeAll()
                }
            case let .update(index):
                if let tableIndex = applyUpdate(at: index, item: update.items.first) {
                    mutatedIndices.insert(tableIndex)
                } else {
                    mutatedIndices.removeAll()
                }
            }
        }

        let mutatedRows = IndexSet(mutatedIndices.filter { timelineRows.indices.contains($0) })

        Logger.timelineTableView.info(
            """
            timeline update: \(updates.count) change(s) touching \(touchedRows) row(s) \
            of \(self.timelineRows.count) (structural: \(isStructural), reset: \(didReset))
            """
        )

        // The apply, the height re-note and the compensating scroll are one
        // visual step, so the intermediate geometry must not be presented. A
        // zero duration also keeps the clamp in `restoreScrollAnchor` reading
        // the settled document height rather than an animating one, and it
        // stops a re-noted row being clipped to its old frame while the
        // implicit row animation runs (MATRIX-49).
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false

            if isStructural {
                dataSource?.apply(snapshot, animatingDifferences: false)
            }

            reloadRows(mutatedRows)
            noteHeightChanges(mutatedRows, context: "timeline update")

            guard let anchor else { return }
            tableView.tile()
            restoreScrollAnchor(anchor)
        }
    }

    private func applyReset() {
        timelineRows = timeline.displayItems.map(\.row)
        heightCache.invalidateAll()
        rowRevisions.removeAll()
        leadingDecorationCount = 0
        trailingDecorationCount = 0
        refreshDecorationRows(applyingSnapshot: false)
        rebuildSnapshot()
    }

    /// Returns the table index the rows were inserted at, or nil if the change
    /// did not match local state and forced a rebuild.
    @discardableResult
    private func applyInsert(at index: Int, count: Int, items: [TimelineItem]) -> Int? {
        guard items.count == count,
              TimelineDisplayOrder.isValidInsertIndex(index, count: itemRowCount)
        else {
            applyReset()
            return nil
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
        return tableIndex
    }

    /// Returns the table index the rows were removed from, or nil on a rebuild.
    @discardableResult
    private func applyRemove(at index: Int, count: Int) -> Int? {
        guard count > 0, index >= 0, index + count <= itemRowCount else {
            applyReset()
            return nil
        }

        let tableIndex = index + leadingDecorationCount
        let removed = timelineRows[tableIndex ..< (tableIndex + count)]
        let removedIds = removed.map(\.uniqueId)
        timelineRows.removeSubrange(tableIndex ..< (tableIndex + count))

        for id in removedIds {
            heightCache.invalidate(rowId: id)
            rowRevisions[id] = nil
        }
        deleteSnapshotItems(withIds: removedIds)
        return tableIndex
    }

    /// Replaces one row's content in place and returns its table index, so the
    /// caller can reload and re-measure exactly that row.
    private func applyUpdate(at index: Int, item: TimelineItem?) -> Int? {
        guard let item, TimelineDisplayOrder.isValidIndex(index, count: itemRowCount) else {
            applyReset()
            return nil
        }

        let tableIndex = index + leadingDecorationCount
        let row = item.row
        let previousId = timelineRows[tableIndex].uniqueId
        timelineRows[tableIndex] = row

        guard row.uniqueId == previousId else {
            // A replacement that also changes identity is structural, not a
            // content update; fall back rather than leave the snapshot stale.
            applyReset()
            return nil
        }

        rowRevisions[row.uniqueId, default: 0] += 1
        return tableIndex
    }

    /// Moves recorded indices across an insertion.
    private static func shift(_ indices: Set<Int>, insertedAt index: Int, count: Int) -> Set<Int> {
        Set(indices.map { $0 >= index ? $0 + count : $0 })
    }

    /// Moves recorded indices across a removal, dropping any that were removed.
    private static func shift(_ indices: Set<Int>, removedAt index: Int, count: Int) -> Set<Int> {
        Set(indices.compactMap { current in
            if current < index { return current }
            if current < index + count { return nil }
            return current - count
        })
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

    /// Redraws the given rows without re-applying the snapshot.
    ///
    /// `NSTableView` caches prepared views, so a content change that does not
    /// move rows still needs an explicit reload to show.
    private func reloadRows(_ rows: IndexSet) {
        guard !rows.isEmpty else { return }
        tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
    }

    /// Asks the table to re-measure exactly the rows whose content mutated.
    private func noteHeightChanges(_ rows: IndexSet, context: String) {
        guard !rows.isEmpty else {
            Logger.timelineTableView.debug("\(context, privacy: .public): no row content mutations, heights kept")
            return
        }
        Logger.timelineTableView.debug(
            "\(context, privacy: .public): re-measuring \(rows.count) mutated row(s) of \(self.timelineRows.count)"
        )
        tableView.noteHeightOfRows(withIndexesChanged: rows)
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
    /// running at the oldest end.
    func listenForPaginationActivity() {
        let status = withObservationTracking {
            timeline.paginating
        } onChange: { [weak self] in
            Task { @MainActor in self?.listenForPaginationActivity() }
        }

        Logger.timelineTableView.debug("pagination status: \(status.debugDescription, privacy: .public)")
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

    private var wantsPaginationRow: Bool {
        if case .paginating = timeline.paginating { return true }
        return false
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
        let paginationRow: TimelineRow? = wantsPaginationRow
            ? .paginationActivity(uniqueId: Self.paginationRowId)
            : nil

        let currentTyping = leadingDecorationCount > 0 ? timelineRows.first : nil
        let currentPagination = trailingDecorationCount > 0 ? timelineRows.last : nil

        let typingChanged = currentTyping?.uniqueId != typingRow?.uniqueId
        let paginationChanged = (currentPagination == nil) != (paginationRow == nil)
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

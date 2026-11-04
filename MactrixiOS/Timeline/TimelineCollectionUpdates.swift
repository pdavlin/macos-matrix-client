import Models
import OSLog
import UIKit

// MARK: - Diff-driven updates

extension TimelineCollectionController {
    /// Applies everything the feed changed since the last update.
    ///
    /// The Mac `applyPendingTimelineChanges` in UIKit form. Cost follows the
    /// diff, not the timeline. Structural changes apply now, as one atomic
    /// visual step with the anchor compensation. Content-only changes queue
    /// for the drain, which spends a frame budget on them.
    func applyPendingTimelineChanges() {
        let updates = feed.drainRowChanges()
        guard !updates.isEmpty else { return }

        // Captured against the old rows and the old geometry.
        let isStructural = updates.contains { $0.change.isStructural }
        let anchor = isStructural ? currentScrollAnchor() : nil

        var regroupedIds: Set<String> = []
        var didReset = false

        for update in updates {
            switch update.change {
            case .reset:
                applyReset()
                didReset = true
            case let .insert(index, count):
                applyInsert(at: index, count: count, rows: update.rows)
            case let .remove(index, count):
                applyRemove(at: index, count: count)
            case let .update(index):
                enqueueUpdate(at: index, row: update.rows.first)
                continue
            }
            regroupedIds.formUnion(regroupAfter(update.change))
        }

        Logger.timelineIOS.info(
            """
            timeline update: \(updates.count) change(s) over \(self.rows.count) row(s) \
            (structural: \(isStructural), reset: \(didReset)), \(self.pendingRowUpdates.count) queued
            """
        )

        if isStructural {
            applySnapshot(restoring: anchor)
            for id in regroupedIds {
                guard let index = snapshot.indexOfItem(id) else { continue }
                reconfigureVisibleCell(atRow: index)
            }
            schedulePendingFocusScroll()
        }

        scheduleRowUpdateDrain()
    }

    /// Re-answers sender grouping around a structural change, and returns the
    /// identities whose answer changed.
    private func regroupAfter(_ change: TimelineDisplayChange) -> [String] {
        let itemRange = TimelineSenderGrouping.rowsToRegroup(after: change, rowCount: itemRowCount)
        let rowRange = (itemRange.lowerBound + leadingDecorationCount) ..< (itemRange.upperBound + leadingDecorationCount)
        return regroup(rowRange).map { rows[$0].uniqueId }
    }

    private func applyReset() {
        rows = feed.displayRows
        heightCache.invalidateAll()
        rowRevisions.removeAll()
        senderHeaders.removeAll()
        // Every row is rebuilt from the source of truth, which already holds
        // the content the queue was holding.
        pendingRowUpdates.removeAll()
        leadingDecorationCount = 0
        trailingDecorationCount = 0
        refreshDecorationRows(applying: false)
        regroup(0 ..< rows.count)
        rebuildSnapshot()
    }

    private func applyInsert(at index: Int, count: Int, rows inserted: [TimelineRow]) {
        let ids = inserted.map(\.uniqueId)
        // A duplicate identity would trap the diffable data source; a state
        // that produces one is a desync, and a rebuild is always correct.
        guard inserted.count == count,
              TimelineDisplayOrder.isValidInsertIndex(index, count: itemRowCount),
              Set(ids).count == ids.count,
              !ids.contains(where: { snapshot.indexOfItem($0) != nil })
        else {
            applyReset()
            return
        }

        let rowIndex = index + leadingDecorationCount
        // Resolved before the splice: after it, this position holds a new row.
        // One section, so an insert at the oldest end lands before the
        // pagination row, and an insert past every row appends.
        let beforeId = rowIndex < rows.count ? rows[rowIndex].uniqueId : nil
        rows.insert(contentsOf: inserted, at: rowIndex)

        if let beforeId {
            snapshot.insertItems(ids, beforeItem: beforeId)
        } else {
            appendToSnapshot(ids)
        }
    }

    private func applyRemove(at index: Int, count: Int) {
        guard count > 0, index >= 0, index + count <= itemRowCount else {
            applyReset()
            return
        }

        let rowIndex = index + leadingDecorationCount
        let removedIds = rows[rowIndex ..< (rowIndex + count)].map(\.uniqueId)
        rows.removeSubrange(rowIndex ..< (rowIndex + count))

        for id in removedIds {
            heightCache.invalidate(rowId: id)
            rowRevisions[id] = nil
            senderHeaders.remove(id)
        }
        // A re-inserted identity must not inherit a payload queued against
        // the copy that left.
        pendingRowUpdates.remove(uniqueIds: removedIds)
        deleteSnapshotItems(removedIds)
    }

    /// Queues one row's new content for the drain. A replacement that changes
    /// identity is structural, so it rebuilds instead.
    private func enqueueUpdate(at index: Int, row: TimelineRow?) {
        guard let row,
              TimelineDisplayOrder.isValidIndex(index, count: itemRowCount),
              row.uniqueId == rows[index + leadingDecorationCount].uniqueId
        else {
            applyReset()
            return
        }
        pendingRowUpdates.enqueue(uniqueId: row.uniqueId, payload: row)
    }

    func appendToSnapshot(_ ids: [String]) {
        if snapshot.numberOfSections == 0 {
            snapshot.appendSections([0])
        }
        snapshot.appendItems(ids, toSection: 0)
    }

    /// Deletes snapshot items, ignoring identities the snapshot no longer
    /// holds. A reset earlier in the same batch can already have dropped them.
    func deleteSnapshotItems(_ ids: [String]) {
        let present = ids.filter { snapshot.indexOfItem($0) != nil }
        guard !present.isEmpty else { return }
        snapshot.deleteItems(present)
    }

    /// Rebuilds the whole snapshot. Only a reset and the initial load take
    /// this path.
    func rebuildSnapshot() {
        var fresh = NSDiffableDataSourceSnapshot<Int, String>()
        fresh.appendSections([0])
        fresh.appendItems(rows.map(\.uniqueId), toSection: 0)
        snapshot = fresh
        UIView.performWithoutAnimation {
            dataSource?.apply(snapshot, animatingDifferences: false)
        }
    }

    /// Applies the snapshot and holds the anchor row still, as one step.
    ///
    /// No animation: the apply and the compensating offset must not present
    /// the geometry between them (the MATRIX-49 reason on the Mac).
    func applySnapshot(restoring anchor: ScrollAnchor?) {
        UIView.performWithoutAnimation {
            dataSource?.apply(snapshot, animatingDifferences: false)
            collectionView.layoutIfNeeded()
            if let anchor {
                restoreScrollAnchor(anchor)
            }
        }
        scheduleScrollReport()
    }
}

// MARK: - Decoration rows

extension TimelineCollectionController {
    private static let typingRowPrefix = "mactrix.timeline.typing"
    private static let paginationRowId = "mactrix.timeline.paginationActivity"
    private static let paginationFailureRowPrefix = "mactrix.timeline.paginationFailure"

    /// The oldest-end decoration for the current state. A failure outranks
    /// activity, and the failure text is part of the identity, so a new
    /// message is a new row with its own measured height (as on the Mac).
    private var wantedPaginationRow: TimelineRow? {
        if let failure = feed.paginationFailure {
            return .paginationFailure(uniqueId: "\(Self.paginationFailureRowPrefix):\(failure)", message: failure)
        }
        if feed.isPaginating {
            return .paginationActivity(uniqueId: Self.paginationRowId)
        }
        return nil
    }

    /// Adds, removes, or re-labels the decoration rows to match the feed.
    ///
    /// With `applying` false only `rows` changes: the caller rebuilds the
    /// snapshot from `rows` next (the initial load and a reset).
    ///
    /// The typing row's identity carries the names it shows, so a change of
    /// who types is a delete plus an insert, and the height cache stays
    /// honest. A typing row appearing at the newest end moves every row while
    /// the reader is scrolled up, so the apply carries the anchor.
    func refreshDecorationRows(applying: Bool) {
        let names = feed.typingNames
        let typingRow: TimelineRow? = names.isEmpty
            ? nil
            : .typingIndicator(uniqueId: "\(Self.typingRowPrefix):\(names.joined(separator: "|"))", names: names)
        let paginationRow = wantedPaginationRow

        let currentTyping = leadingDecorationCount > 0 ? rows.first : nil
        let currentPagination = trailingDecorationCount > 0 ? rows.last : nil

        let typingChanged = currentTyping?.uniqueId != typingRow?.uniqueId
        let paginationChanged = currentPagination?.uniqueId != paginationRow?.uniqueId
        guard typingChanged || paginationChanged else { return }

        let anchor = applying && typingChanged ? currentScrollAnchor() : nil

        if typingChanged {
            if let currentTyping {
                rows.removeFirst()
                leadingDecorationCount = 0
                heightCache.invalidate(rowId: currentTyping.uniqueId)
                if applying {
                    deleteSnapshotItems([currentTyping.uniqueId])
                }
            }
            if let typingRow {
                if applying {
                    if let first = snapshot.itemIdentifiers.first {
                        snapshot.insertItems([typingRow.uniqueId], beforeItem: first)
                    } else {
                        appendToSnapshot([typingRow.uniqueId])
                    }
                }
                rows.insert(typingRow, at: 0)
                leadingDecorationCount = 1
            }
        }

        if paginationChanged {
            if let currentPagination {
                rows.removeLast()
                trailingDecorationCount = 0
                heightCache.invalidate(rowId: currentPagination.uniqueId)
                if applying {
                    deleteSnapshotItems([currentPagination.uniqueId])
                }
            }
            if let paginationRow {
                rows.append(paginationRow)
                trailingDecorationCount = 1
                if applying {
                    appendToSnapshot([paginationRow.uniqueId])
                }
            }
        }

        guard applying else { return }
        applySnapshot(restoring: anchor)
    }
}

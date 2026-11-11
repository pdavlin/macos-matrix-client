import Foundation

/// A display-ordered change together with the rows it brings (MATRIX-142).
///
/// The row-based twin of Core's `TimelineDisplayUpdate`, which carries SDK
/// items. A row source with rows that no SDK item stands behind (the merged
/// timeline's date dividers and source notes) publishes these instead. The
/// container replays them in order, as it replays `TimelineDisplayUpdate`.
public struct TimelineRowDisplayUpdate {
    public let change: TimelineDisplayChange
    /// The inserted rows (`.insert`), or the one replacement row (`.update`),
    /// in display order. Empty for removals and resets.
    public let rows: [TimelineRow]

    public init(change: TimelineDisplayChange, rows: [TimelineRow] = []) {
        self.change = change
        self.rows = rows
    }
}

/// The display changes that turn one row array into another, matched by row
/// identifier (MATRIX-142 Phase B).
///
/// The merged timeline is recomputed as a whole, so it has no SDK diff to
/// mirror. This compares the previous rows with the new rows instead, and
/// states the difference in the container's change language
/// (`TimelineDisplayChange`), so the container keeps its diff-sized updates,
/// its scroll anchor, and its height cache.
public enum TimelineRowDiff {
    /// The changes from `old` to `new`.
    ///
    /// **Order.** Apply the changes in the order returned:
    ///
    /// 1. Removals, from the highest index down, in `old`'s indices. Each
    ///    leaves the indices below it alone.
    /// 2. Insertions, from the lowest index up, in `new`'s indices. Each
    ///    lands at its final position.
    /// 3. Updates, in `new`'s indices: rows whose identifier stays and whose
    ///    content changed (`hasSameContent` is false).
    ///
    /// Adjacent removals or insertions form one change with a count, so a
    /// back-pagination batch is one insert.
    ///
    /// **Moves.** The rows that keep their place are the longest run of
    /// common rows that keeps its order (a longest increasing subsequence,
    /// O(k log k) for k common rows; O(k) when nothing moved, the usual case).
    /// A common row outside that run moved: it is removed and inserted again.
    ///
    /// **Reset.** One `.reset` when `old` is empty, or when no row is common
    /// to both: the container rebuilds from the new rows.
    ///
    /// Cost: O(n + m) hashing for n old and m new rows, plus the move pass.
    ///
    /// - Precondition: identifiers are unique inside `old` and inside `new`.
    ///   A repeated identifier in `old` returns `.reset`; the caller removes
    ///   repeats from `new` first (`TimelineRowIdentity.removingDuplicates`).
    /// - Parameters:
    ///   - old: the rows the container holds now.
    ///   - new: the rows it must hold after the changes.
    ///   - id: the identifier of a row.
    ///   - hasSameContent: true when two rows with one identifier draw the
    ///     same.
    /// - Returns: the changes, empty when nothing changed.
    public static func changes<Element>(
        from old: [Element],
        to new: [Element],
        id: (Element) -> String,
        hasSameContent: (Element, Element) -> Bool
    ) -> [TimelineDisplayChange] {
        if old.isEmpty {
            return new.isEmpty ? [] : [.reset]
        }

        var oldIndexById: [String: Int] = [:]
        oldIndexById.reserveCapacity(old.count)
        for (index, element) in old.enumerated() {
            oldIndexById[id(element)] = index
        }
        guard oldIndexById.count == old.count else { return [.reset] }

        var commonOld: [Int] = []
        var commonNew: [Int] = []
        commonOld.reserveCapacity(min(old.count, new.count))
        commonNew.reserveCapacity(min(old.count, new.count))
        for (index, element) in new.enumerated() {
            guard let oldIndex = oldIndexById[id(element)] else { continue }
            commonOld.append(oldIndex)
            commonNew.append(index)
        }
        guard !commonOld.isEmpty else { return [.reset] }

        let kept = longestIncreasingSubsequenceMask(commonOld)
        var keptOld = [Bool](repeating: false, count: old.count)
        var keptNew = [Bool](repeating: false, count: new.count)
        var updated: [Int] = []
        for position in commonOld.indices where kept[position] {
            let oldIndex = commonOld[position]
            let newIndex = commonNew[position]
            keptOld[oldIndex] = true
            keptNew[newIndex] = true
            if !hasSameContent(old[oldIndex], new[newIndex]) {
                updated.append(newIndex)
            }
        }

        var changes: [TimelineDisplayChange] = []
        var index = old.count - 1
        while index >= 0 {
            guard !keptOld[index] else {
                index -= 1
                continue
            }
            var start = index
            while start > 0, !keptOld[start - 1] {
                start -= 1
            }
            changes.append(.remove(index: start, count: index - start + 1))
            index = start - 1
        }

        index = 0
        while index < new.count {
            guard !keptNew[index] else {
                index += 1
                continue
            }
            var end = index
            while end + 1 < new.count, !keptNew[end + 1] {
                end += 1
            }
            changes.append(.insert(index: index, count: end - index + 1))
            index = end + 1
        }

        changes.append(contentsOf: updated.map { TimelineDisplayChange.update(index: $0) })
        return changes
    }

    /// `changes(from:to:id:hasSameContent:)`, with the rows each change
    /// brings, read from `new`.
    public static func updates<Element>(
        from old: [Element],
        to new: [Element],
        id: (Element) -> String,
        hasSameContent: (Element, Element) -> Bool,
        row: (Element) -> TimelineRow
    ) -> [TimelineRowDisplayUpdate] {
        changes(from: old, to: new, id: id, hasSameContent: hasSameContent).map { change in
            switch change {
            case let .insert(index, count):
                TimelineRowDisplayUpdate(change: change, rows: new[index ..< index + count].map(row))
            case let .update(index):
                TimelineRowDisplayUpdate(change: change, rows: [row(new[index])])
            case .remove, .reset:
                TimelineRowDisplayUpdate(change: change)
            }
        }
    }

    /// Marks the elements of one longest strictly increasing subsequence of
    /// `values`. O(n) when `values` is already increasing, else O(n log n)
    /// (patience sorting with back links).
    static func longestIncreasingSubsequenceMask(_ values: [Int]) -> [Bool] {
        if zip(values, values.dropFirst()).allSatisfy({ $0 < $1 }) {
            return [Bool](repeating: true, count: values.count)
        }
        // tails[length - 1]: the index of the smallest last value of an
        // increasing subsequence of that length found so far.
        var tails: [Int] = []
        var previous = [Int](repeating: -1, count: values.count)
        for (index, value) in values.enumerated() {
            var low = 0
            var high = tails.count
            while low < high {
                let middle = (low + high) / 2
                if values[tails[middle]] < value {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            if low > 0 {
                previous[index] = tails[low - 1]
            }
            if low == tails.count {
                tails.append(index)
            } else {
                tails[low] = index
            }
        }
        var mask = [Bool](repeating: false, count: values.count)
        var cursor = tails.last ?? -1
        while cursor >= 0 {
            mask[cursor] = true
            cursor = previous[cursor]
        }
        return mask
    }
}

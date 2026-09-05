import Foundation

/// One change to the display-ordered (newest-first) timeline array, derived
/// from a single SDK timeline diff (S-34).
///
/// The container replays these instead of comparing the old and new row
/// arrays. That is what makes an update cost proportional to the diff rather
/// than to the length of the timeline: no reversed copy, no full identifier
/// rescan, no reload of every row when one message changes.
///
/// Indices are display indices, already mirrored out of the SDK's
/// oldest-first order by `TimelineDisplayOrder`.
public enum TimelineDisplayChange: Equatable {
    /// `count` rows were inserted starting at `index`.
    case insert(index: Int, count: Int)
    /// `count` rows were removed starting at `index`.
    case remove(index: Int, count: Int)
    /// The row at `index` was replaced with new content for the same identity.
    case update(index: Int)
    /// The whole array was replaced; the container must rebuild.
    case reset

    /// True when the change moves rows, so the container must re-apply its
    /// snapshot and compensate the scroll anchor. A content-only update does
    /// neither.
    public var isStructural: Bool {
        switch self {
        case .update:
            return false
        case .insert, .remove, .reset:
            return true
        }
    }

    /// How many rows the change touches. Summed across a batch, this is the
    /// per-update cost the acceptance criteria track.
    public var rowCount: Int {
        switch self {
        case let .insert(_, count), let .remove(_, count):
            return count
        case .update:
            return 1
        case .reset:
            return 0
        }
    }
}

/// Index math for mirroring an SDK-ordered (oldest-first) timeline onto the
/// display-ordered (newest-first) array the container renders.
///
/// The table is not flipped and rows are newest-first, so display index 0 is
/// the newest event and sits at the bottom of the viewport.
public enum TimelineDisplayOrder {
    /// Display index of an existing SDK index, where `count` is the number of
    /// elements the array holds.
    public static func displayIndex(ofSdkIndex sdkIndex: Int, count: Int) -> Int {
        count - 1 - sdkIndex
    }

    /// Display index an SDK insert at `sdkIndex` lands on, where `count` is
    /// the element count *before* the insert.
    ///
    /// One more than `displayIndex(ofSdkIndex:count:)` would give for the same
    /// index, because the insert grows the array: inserting at SDK index 0
    /// (the oldest end) appends at the display end.
    public static func displayInsertIndex(ofSdkIndex sdkIndex: Int, countBeforeInsert count: Int) -> Int {
        count - sdkIndex
    }

    /// True when `index` addresses an existing element of a `count`-element
    /// array. Callers validate SDK indices before applying them, so a diff
    /// that disagrees with local state resynchronizes instead of trapping.
    public static func isValidIndex(_ index: Int, count: Int) -> Bool {
        index >= 0 && index < count
    }

    /// True when `index` is a legal insertion point in a `count`-element array.
    public static func isValidInsertIndex(_ index: Int, count: Int) -> Bool {
        index >= 0 && index <= count
    }
}

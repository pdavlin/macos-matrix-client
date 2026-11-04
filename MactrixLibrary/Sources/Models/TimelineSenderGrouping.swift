import Foundation

/// Which message rows open a sender run and draw the profile header (MATRIX-85).
///
/// The rule is the one `TimelineGroups.insertEnd` applies: consecutive
/// message-like events from the same sender form one group, and any other row
/// between them (a day divider, the read marker, a state event) ends it. The
/// grouped model rebuilds the whole timeline per update, so a row container
/// asks this per row instead and re-asks only for the rows a change can affect.
///
/// The header changes a row's height, so the container treats a changed answer
/// like any other height change and re-measures that row.
public enum TimelineSenderGrouping {
    /// Whether `row` draws the sender header, given the row just older than it
    /// in display order.
    ///
    /// False for every row that is not a message: they draw no header at all.
    public static func showsSenderHeader(_ row: TimelineRow, olderNeighbor: TimelineRow?) -> Bool {
        guard case let .message(_, event, _, _) = row else { return false }
        guard case let .message(_, olderEvent, _, _)? = olderNeighbor else { return true }
        return olderEvent.sender != event.sender
    }

    /// Display indices whose header answer can change after `change`, where
    /// `rowCount` is the row count after the change.
    ///
    /// A row's answer depends on its own content and on its older neighbor
    /// (index + 1). So a change can affect the rows it touches and the row
    /// just newer than it (index - 1), whose older neighbor it replaced.
    public static func rowsToRegroup(after change: TimelineDisplayChange, rowCount: Int) -> Range<Int> {
        let range: Range<Int> = switch change {
        case let .insert(index, count):
            (index - 1) ..< (index + count)
        case let .remove(index, _):
            (index - 1) ..< index
        case let .update(index):
            (index - 1) ..< (index + 1)
        case .reset:
            0 ..< rowCount
        }
        let lower = min(max(range.lowerBound, 0), rowCount)
        let upper = min(max(range.upperBound, lower), rowCount)
        return lower ..< upper
    }
}

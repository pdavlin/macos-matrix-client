import Foundation

/// Which day the floating sticky day pill shows (MATRIX-136).
///
/// The pill floats at the top of the timeline while it scrolls and names the
/// day of the content under it. The container reads which rows sit under the
/// pill on each bounds change and asks this type for the day. No other work
/// runs per scroll frame.
public enum TimelineStickyDay {
    /// The day to show for the rows under the sticky pill.
    ///
    /// - Parameters:
    ///   - rows: every table row, newest first (index 0 is the newest end).
    ///   - rowsAtTopEdge: the row indices under the pill. The table is not
    ///     flipped, so the visually topmost row is the highest index.
    ///   - calendar: the calendar that decides where a day starts. Pass the
    ///     one the timeline groups senders with, the reader's own.
    /// - Returns: the start of the day to show, or nil to hide the pill. The
    ///   pill hides when a real date divider sits under it, so two pills never
    ///   show at the same time, and when no row near the top carries a date.
    ///
    /// The day comes from the topmost row's event date. A row without one
    /// (the read marker, the timeline start, a decoration row) takes the
    /// date of the nearest older row that has one, which is the day that
    /// row sits in. If no older row has a date, the nearest newer row's date
    /// is used.
    public static func day(
        rows: [TimelineRow],
        rowsAtTopEdge: Range<Int>,
        calendar: Calendar
    ) -> Date? {
        let edge = rowsAtTopEdge.clamped(to: rows.indices)
        guard let topIndex = edge.last else { return nil }
        if edge.contains(where: { rows[$0].isDateDivider }) {
            return nil
        }

        let older = rows[topIndex...].lazy.compactMap(\.stickyDayDate).first
        let newer = rows[..<topIndex].reversed().lazy.compactMap(\.stickyDayDate).first
        guard let date = older ?? newer else { return nil }
        return calendar.startOfDay(for: date)
    }
}

extension TimelineRow {
    /// True for a date divider row.
    var isDateDivider: Bool {
        if case .virtual(_, .dateDivider) = self { return true }
        return false
    }

    /// The date that places this row in a day, or nil for rows without one.
    var stickyDayDate: Date? {
        switch self {
        case let .message(_, event, _, _):
            return event.date
        case let .state(_, event, _):
            return event.date
        case let .virtual(_, .dateDivider(date)):
            return date
        case .virtual, .typingIndicator, .paginationActivity, .paginationFailure, .unsupported:
            return nil
        }
    }
}

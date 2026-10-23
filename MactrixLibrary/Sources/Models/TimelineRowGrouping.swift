import Foundation

/// The vertical gap above a message row, by how the message relates in time
/// and sender to the message before it (MATRIX-68).
///
/// The bands are Beeper's. Beeper states them as the gap *below* the earlier
/// message of a pair; the row model states the same pair as the gap *above*
/// the later one, with the same value. Same pair, same gap — only the owner
/// moves, and it moves so that a new message at the newest end can never
/// change a row that is already laid out (see `TimelineRowGrouping`).
///
/// The point values live in `RhythmToken`; this type only names the band.
public enum TimelineGapBand: String, Equatable, Hashable, Sendable, CaseIterable {
    /// No rhythm gap: the row keeps the spacing it had before MATRIX-68.
    ///
    /// Taken when the row before is not a message (a state event, a divider,
    /// a decoration row, or nothing at all) and when the two messages fall on
    /// different calendar days, where a date divider already sits between them.
    case none
    /// Same sender, within a minute.
    case sameSenderBurst
    /// Another sender, within a minute.
    case senderTurn
    /// More than a minute apart.
    case shortPause
    /// More than five minutes apart.
    case pause
    /// More than four hours apart.
    case longPause

    /// Upper bound, in seconds, of the burst bands. Strictly greater moves the
    /// pair into `shortPause`.
    static let burstLimit: TimeInterval = 60
    /// Strictly greater than this many seconds is a `pause`.
    static let shortPauseLimit: TimeInterval = 5 * 60
    /// Strictly greater than this many seconds is a `longPause`.
    static let pauseLimit: TimeInterval = 240 * 60
}

/// What a row needs to know about the row before it to place itself in a run:
/// who sent it and when.
///
/// Only message rows have one. Every other row breaks a run, which is the
/// same as having no predecessor at all — that equivalence is what lets the
/// decoration rows come and go without regrouping anything.
public struct TimelineGroupingAnchor: Equatable, Sendable {
    /// The sender's Matrix user ID. IDs, not display names: two senders can
    /// share a name, and a name can resolve after the row is laid out.
    public let senderId: String
    public let date: Date

    public init(senderId: String, date: Date) {
        self.senderId = senderId
        self.date = date
    }
}

/// How a message row sits in its run of messages (MATRIX-68).
///
/// Derived from the row and the row *before* it in time, never from the row
/// after it. A run grows at the newest end, so deriving from the successor
/// would make every arriving message change the message above it — a
/// re-measure and a reload per arrival, on a row that is already on screen.
/// Deriving from the predecessor confines that cost to the rare structural
/// change that lands *between* two existing rows, or before the oldest one.
///
/// The run rule is Beeper's: a run breaks on a sender change, after any row
/// that is not a message, and across a calendar day. Time alone does not break
/// a run: a sender who comes back three hours later continues it, and only the
/// gap above the row says how long the pause was.
public struct TimelineRowGrouping: Equatable, Hashable, Sendable {
    /// True when the row continues the previous message's run, so the row
    /// draws no profile header.
    public let isContinuation: Bool
    /// The spacing band above the row.
    public let gap: TimelineGapBand

    public init(isContinuation: Bool, gap: TimelineGapBand) {
        self.isContinuation = isContinuation
        self.gap = gap
    }

    /// A row that starts a run with no rhythm gap: the grouping every message
    /// row had before MATRIX-68, and the one a row takes before its
    /// predecessor is known.
    public static let standalone = TimelineRowGrouping(isContinuation: false, gap: .none)

    /// The profile header shows on the first message of a run only.
    public var showsProfileHeader: Bool { !isContinuation }

    /// Groups a message against the message-like row before it in time.
    ///
    /// - Parameters:
    ///   - anchor: The row being grouped.
    ///   - predecessor: The chronologically earlier neighbour's anchor, or nil
    ///     when that neighbour is not a message or does not exist.
    ///   - calendar: Decides what "the same day" means. The app passes the
    ///     user's calendar, which is the one the SDK's date dividers follow.
    public static func derive(
        _ anchor: TimelineGroupingAnchor,
        after predecessor: TimelineGroupingAnchor?,
        calendar: Calendar
    ) -> TimelineRowGrouping {
        guard let predecessor else { return .standalone }
        // A date divider sits between messages on different days, and it is
        // a run break and a gap of its own.
        guard calendar.isDate(anchor.date, inSameDayAs: predecessor.date) else { return .standalone }

        let sameSender = anchor.senderId == predecessor.senderId
        let interval = anchor.date.timeIntervalSince(predecessor.date)

        let gap: TimelineGapBand = if interval > TimelineGapBand.pauseLimit {
            .longPause
        } else if interval > TimelineGapBand.shortPauseLimit {
            .pause
        } else if interval > TimelineGapBand.burstLimit {
            .shortPause
        } else {
            // Includes a negative interval: a local echo can carry a clock
            // that runs ahead of the server's, and that pair is still a burst.
            sameSender ? .sameSenderBurst : .senderTurn
        }
        return TimelineRowGrouping(isContinuation: sameSender, gap: gap)
    }
}

// MARK: - Row-model integration

public extension TimelineRow {
    /// Who sent this row and when, for the row that follows it. Nil for every
    /// row that is not a message, which is what makes those rows break a run.
    var groupingAnchor: TimelineGroupingAnchor? {
        guard case let .message(_, event, _, _) = self else { return nil }
        return TimelineGroupingAnchor(senderId: event.sender, date: event.date)
    }

    /// The row's place in its run. Nil for every row that is not a message.
    var grouping: TimelineRowGrouping? {
        heightFingerprint?.grouping
    }

    /// This row with its grouping re-derived against `predecessor`, the row
    /// before it in time. Rows that are not messages come back unchanged.
    func regrouped(after predecessor: TimelineRow?, calendar: Calendar) -> TimelineRow {
        guard case let .message(uniqueId, event, kind, fingerprint) = self,
              let anchor = groupingAnchor
        else {
            return self
        }
        let grouping = TimelineRowGrouping.derive(anchor, after: predecessor?.groupingAnchor, calendar: calendar)
        guard grouping != fingerprint.grouping else { return self }
        return .message(uniqueId: uniqueId, event: event, kind: kind, heightFingerprint: fingerprint.with(grouping: grouping))
    }
}

/// Grouping over the container's row array (MATRIX-68).
///
/// The container's rows are **newest first** (S-34 display order), so the row
/// before row `i` in time is row `i + 1`, not `i - 1`. That inversion is the
/// whole reason this lives here, under test, instead of inline in the
/// container.
public enum TimelineRowRegrouping {
    /// Index of the chronological predecessor of `index` in a newest-first
    /// array.
    public static func predecessorIndex(of index: Int) -> Int {
        index + 1
    }

    /// Index of the chronological successor of `index` in a newest-first
    /// array: the row whose grouping reads this one.
    public static func successorIndex(of index: Int) -> Int {
        index - 1
    }

    /// Re-derives the grouping of the row at `index` from its predecessor, and
    /// reports whether it changed. An index outside the array is a no-op.
    @discardableResult
    public static func regroupRow(at index: Int, in rows: inout [TimelineRow], calendar: Calendar) -> Bool {
        guard rows.indices.contains(index) else { return false }
        let predecessorIndex = predecessorIndex(of: index)
        let predecessor = rows.indices.contains(predecessorIndex) ? rows[predecessorIndex] : nil
        let regrouped = rows[index].regrouped(after: predecessor, calendar: calendar)
        guard regrouped.grouping != rows[index].grouping else { return false }
        rows[index] = regrouped
        return true
    }

    /// Groups every row. One pass, each row against its own predecessor, so it
    /// costs what the reset that calls it already costs: one visit per row.
    ///
    /// Order does not matter: a row's grouping reads its predecessor's sender
    /// and date, never the predecessor's grouping, so there is no chain to
    /// resolve.
    public static func regroupAll(_ rows: inout [TimelineRow], calendar: Calendar) {
        for index in rows.indices {
            regroupRow(at: index, in: &rows, calendar: calendar)
        }
    }
}

import Foundation
import Models

/// The reply details a timeline loads itself (MATRIX-230).
///
/// The SDK leaves a reply's quote pending or unavailable when the replied-to
/// event is not in the timeline, and `LiveTimeline` loads it with
/// `Timeline.loadReplyDetails(eventIdStr:)`. That call returns the details and
/// changes no timeline item, so no row update follows. The rows that quote
/// the event draw the new quote by themselves (they read
/// `loadedReplyDetails`), but keep the height of the placeholder until the
/// container measures them again. This notification tells the container.
public extension LiveTimeline {
    /// Posted on the main actor when an entry of `loadedReplyDetails` loads.
    /// The object is the `LiveTimeline`; `loadedReplyEventIdKey` holds the
    /// replied-to event's ID.
    static let replyDetailsDidLoad = Notification.Name("LiveTimeline.replyDetailsDidLoad")
    static let loadedReplyEventIdKey = "eventId"

    internal func postReplyDetailsDidLoad(eventId: String) {
        NotificationCenter.default.post(
            name: Self.replyDetailsDidLoad,
            object: self,
            userInfo: [Self.loadedReplyEventIdKey: eventId]
        )
    }
}

/// What a loaded reply quote does to the container's rows (MATRIX-230).
public enum LoadedReplyQuote {
    /// Puts `quote` in the fingerprint of each row that quotes `eventId` and
    /// that `isInTimeline` accepts, and returns the indices of the rows whose
    /// height it can change: the rows to measure again.
    ///
    /// The test is the row update's (MATRIX-63), `heightIsUnchanged(from:to:)`,
    /// so a load that changes nothing the quote lays out (a second load of the
    /// same event) measures nothing.
    ///
    /// - Parameter isInTimeline: Whether a row belongs to the timeline that
    ///   loaded the quote. A merged chat holds the rows of several.
    public static func apply(
        _ quote: Models.ReplyQuoteGeometry,
        quoting eventId: String,
        to rows: inout [Models.TimelineRow],
        where isInTimeline: (Models.TimelineRow) -> Bool
    ) -> IndexSet {
        var changed = IndexSet()
        for index in rows.indices {
            let row = rows[index]
            // Cheapest test first: a row that quotes nothing stops at its
            // fingerprint, before the one FFI call of `quotedEventId`.
            guard let updated = row.withReplyQuote(quote), isInTimeline(row), row.quotedEventId == eventId else { continue }
            rows[index] = updated
            if !Models.TimelineRowHeightFingerprint.heightIsUnchanged(from: row, to: updated) {
                changed.insert(index)
            }
        }
        return changed
    }
}

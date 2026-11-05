import Foundation
import Models
import Observation

/// The media sends of one timeline that run in the SDK, each with its join
/// handle cancel (MATRIX-106). MATRIX-107 reads `tickets` and cancels from
/// the local echo row.
///
/// `LiveTimeline.sendMedia(_:)` opens a ticket for each SDK send call and
/// closes it when the join handle's `join()` returns.
@MainActor @Observable
public final class MediaSendTracker {
    /// The open sends, oldest first.
    public private(set) var tickets: [MediaSendTicket] = []

    /// The join handle cancel for each open ticket.
    @ObservationIgnored private var cancellers: [UUID: () -> Void] = [:]

    public init() {}

    /// Opens a ticket for a send that started.
    ///
    /// - Parameters:
    ///   - filenames: the attachment filenames, in send order.
    ///   - isGallery: true for a `sendGallery` call.
    ///   - cancel: calls `cancel()` on the join handle.
    /// - Returns: the new ticket.
    public func begin(filenames: [String], isGallery: Bool, cancel: @escaping () -> Void) -> MediaSendTicket {
        let ticket = MediaSendTicket(filenames: filenames, isGallery: isGallery)
        tickets.append(ticket)
        cancellers[ticket.id] = cancel
        return ticket
    }

    /// Closes a ticket after its `join()` returned.
    ///
    /// - Parameter id: the ticket id.
    public func finish(_ id: UUID) {
        tickets.removeAll { $0.id == id }
        cancellers[id] = nil
    }

    /// Cancels the join handle of a ticket and closes the ticket.
    ///
    /// - Parameter id: the ticket id.
    /// - Returns: true if the ticket was open.
    @discardableResult
    public func cancel(_ id: UUID) -> Bool {
        guard let cancel = cancellers[id] else { return false }
        cancel()
        finish(id)
        return true
    }

    /// Finds the ticket of the send that made a local echo, and binds the
    /// ticket to the echo transaction id, so later calls match at once.
    ///
    /// - Parameters:
    ///   - transactionId: the local echo transaction id.
    ///   - filename: the filename in the local echo content, or nil for a
    ///     gallery. See `MediaSendCorrelation` for the match rule.
    /// - Returns: the bound ticket, or nil if no open ticket matched.
    @discardableResult
    public func bind(localEchoTransactionId transactionId: String, filename: String?) -> MediaSendTicket? {
        guard let index = MediaSendCorrelation.ticketIndex(
            forTransactionId: transactionId,
            filename: filename,
            in: tickets
        ) else { return nil }
        tickets[index].localEchoTransactionId = transactionId
        return tickets[index]
    }

    /// Cancels the join handle of the send that made a local echo.
    ///
    /// - Parameters:
    ///   - transactionId: the local echo transaction id.
    ///   - filename: the filename in the local echo content, or nil for a
    ///     gallery.
    /// - Returns: true if a ticket matched.
    @discardableResult
    public func cancel(localEchoTransactionId transactionId: String, filename: String?) -> Bool {
        guard let ticket = bind(localEchoTransactionId: transactionId, filename: filename) else { return false }
        return cancel(ticket.id)
    }
}

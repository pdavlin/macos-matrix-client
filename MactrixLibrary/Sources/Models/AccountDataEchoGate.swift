import Foundation

/// Decides whether a read of a custom account data event is current. The
/// design of `ChatLabelEchoGate` (MATRIX-77) and `MergedChatEchoGate`
/// (MATRIX-140), for any document type. The bookmarks use it (MATRIX-208).
///
/// `setAccountData` sends the event to the homeserver. The SDK's local
/// store, which `accountData` reads, changes only when sync brings the event
/// back. Between the write and that echo a read returns the old document.
/// Trusting it would undo the write on screen, and a second change in that
/// window would start from the old document and lose the first one.
///
/// So after each write the gate holds the written document until a read
/// returns it, or until `timeout` passes (the echo was lost, or another
/// device wrote in between: then the store is the truth again).
public struct AccountDataEchoGate<Document: Equatable & Sendable>: Sendable {
    public static var defaultTimeout: TimeInterval { 30 }

    private var pending: (document: Document, deadline: Date)?
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = Self.defaultTimeout) {
        self.timeout = timeout
    }

    /// A write of `document` was sent at `now`.
    public mutating func didWrite(_ document: Document, now: Date = .now) {
        pending = (document, now.addingTimeInterval(timeout))
    }

    /// The document a write must start from while an echo is pending, or nil
    /// when the store is current and the caller should read it.
    public mutating func pendingDocument(now: Date = .now) -> Document? {
        guard let pending else { return nil }
        if now >= pending.deadline {
            self.pending = nil
            return nil
        }
        return pending.document
    }

    /// Filters a read. True: adopt the read. False: keep the written
    /// document on screen, because its echo has not arrived.
    ///
    /// - Parameter readDocument: The document the read parsed, or nil when
    ///   the event is unset or did not parse.
    public mutating func accept(_ readDocument: Document?, now: Date = .now) -> Bool {
        guard let pending else { return true }
        if readDocument == pending.document || now >= pending.deadline {
            self.pending = nil
            return true
        }
        return false
    }
}

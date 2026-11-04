import Foundation

/// Decides whether a read of the labels account data is current (MATRIX-77).
///
/// `setAccountData` sends the event to the homeserver; the SDK's local store,
/// which `accountData` reads, only changes when sync brings the event back.
/// Between the write and that echo a read returns the OLD document. Trusting
/// it would undo the write on screen, and a second edit in that window would
/// start from the old document and lose the first one.
///
/// So after each write the gate holds the written document until a read
/// returns it, or until `timeout` passes (the echo was lost, or another
/// device wrote in between: then the store is the truth again).
public struct ChatLabelEchoGate: Sendable {
    public static let defaultTimeout: TimeInterval = 30

    private var pending: (document: ChatLabelDocument, deadline: Date)?
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = Self.defaultTimeout) {
        self.timeout = timeout
    }

    /// A write of `document` was sent at `now`.
    public mutating func didWrite(_ document: ChatLabelDocument, now: Date = .now) {
        pending = (document, now.addingTimeInterval(timeout))
    }

    /// The document a write must start from while an echo is pending, or nil
    /// when the store is current and the caller should read it.
    public mutating func pendingDocument(now: Date = .now) -> ChatLabelDocument? {
        guard let pending else { return nil }
        if now >= pending.deadline {
            self.pending = nil
            return nil
        }
        return pending.document
    }

    /// Filters a read: returns the result to adopt, or nil to keep the
    /// written document on screen because its echo has not arrived.
    public mutating func accept(_ read: ChatLabelReadResult, now: Date = .now) -> ChatLabelReadResult? {
        guard let pending else { return read }
        if case let .parsed(document) = read, document == pending.document {
            self.pending = nil
            return read
        }
        if now >= pending.deadline {
            self.pending = nil
            return read
        }
        return nil
    }
}

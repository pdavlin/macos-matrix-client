import Foundation

/// One request from the view layer to a controller that observes it, with a
/// nonce that tells two equal requests apart (MATRIX-138).
///
/// A plain optional value cannot carry "open the picker for message A" twice
/// in a row: the second write stores an equal value, and an observer that
/// compares values sees no change. The nonce goes up on every request, so
/// each one is new.
public struct NoncedRequest<Payload> {
    /// What the request asks for.
    public let payload: Payload
    /// Goes up by one for each request on the same channel. The first
    /// request has nonce 1.
    public let nonce: Int

    public init(payload: Payload, nonce: Int) {
        self.payload = payload
        self.nonce = nonce
    }
}

extension NoncedRequest: Equatable where Payload: Equatable {}
extension NoncedRequest: Sendable where Payload: Sendable {}

/// The sending side: holds the latest request.
///
/// Usage (inside an `@Observable` owner, so a send is a change observers
/// see):
/// ```swift
/// public internal(set) var pickerRequests = NoncedRequestChannel<EventKey>()
/// func requestPicker(for key: EventKey) { pickerRequests.send(key) }
/// ```
public struct NoncedRequestChannel<Payload> {
    /// The newest request, or nil before the first one.
    public private(set) var latest: NoncedRequest<Payload>?

    public init() {}

    /// Sends a request. Its nonce is one more than the previous request's.
    public mutating func send(_ payload: Payload) {
        latest = NoncedRequest(payload: payload, nonce: (latest?.nonce ?? 0) + 1)
    }
}

/// The receiving side: remembers which requests it has acted on.
///
/// A receiver made after requests were sent must not replay the last one
/// (for example a timeline view made again when the user comes back to a
/// room), so it starts at the channel's current nonce.
///
/// Usage:
/// ```swift
/// var cursor = NoncedRequestCursor(startingAt: owner.pickerRequests.latest)
/// // On each change:
/// if let key = cursor.take(owner.pickerRequests.latest) { openPicker(for: key) }
/// ```
public struct NoncedRequestCursor {
    /// The nonce of the last request this receiver took, or of the request
    /// that was current when it started.
    public private(set) var handledNonce: Int

    /// - Parameter current: The channel's latest request when the receiver
    ///   starts. It counts as handled.
    public init(startingAt current: NoncedRequest<some Any>?) {
        handledNonce = current?.nonce ?? 0
    }

    /// Returns the request's payload if the receiver has not taken it yet,
    /// and marks it as taken. Returns nil for nil, for a request already
    /// taken, and for an older one.
    public mutating func take<Payload>(_ request: NoncedRequest<Payload>?) -> Payload? {
        guard let request, request.nonce > handledNonce else { return nil }
        handledNonce = request.nonce
        return request.payload
    }
}

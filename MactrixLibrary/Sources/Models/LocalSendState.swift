import Foundation

/// Platform-neutral send state of a local echo in the timeline.
///
/// Mirrors the SDK's `EventSendState` without importing it: the SDK owns the
/// send queue and the retry semantics; this type only carries what the rows
/// need to render. The SDK conformance maps its wedge error into a
/// user-readable `message`. Named `sendState` on `EventTimelineItem` (not
/// `localSendState`) because the SDK struct already declares a
/// `localSendState` field of an incompatible type — the S-31 naming lesson.
public enum LocalSendState: Equatable, Sendable {
    /// The event is queued or in flight.
    case sending
    /// The send failed. `isRecoverable` follows the SDK's split: a
    /// recoverable failure disabled the room's send queue (retry re-enables
    /// it), an unrecoverable one wedged this event (retry resends it).
    case sendingFailed(message: String, isRecoverable: Bool)
    /// The event reached the server.
    case sent
}

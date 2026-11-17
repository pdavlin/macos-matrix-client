import Foundation
import MatrixRustSDK
import Models

/// Applies `Models.ReplyRoute` to the SDK (MATRIX-169).
///
/// The pinned SDK (26.04.01) has no reply parameters on the FFI: `Timeline`
/// has `send(msg:)` and `sendReply(msg:eventId:)` only. The SDK takes the
/// relation from the focus of the timeline that sends:
///
/// - On a `.thread(rootEventId:)` timeline, `send` makes a thread message and
///   `sendReply` makes a reply inside the thread.
/// - On a `.live` timeline, `sendReply` forwards the thread relation of the
///   target, if the target has one. A thread root has none, so a reply to a
///   root is a plain reply there.
///
/// So a message for a thread goes out through a timeline with the focus on
/// that thread. This file selects that timeline and builds no relation.
public extension LiveTimeline {
    /// The route of a reply to `target` from this timeline's composer.
    func replyRoute(to target: MatrixRustSDK.EventTimelineItem) -> ReplyRoute {
        var threadRoot: String?
        var hasThreadSummary = false
        if case let .msgLike(content: content) = target.content {
            threadRoot = content.threadRoot
            hasThreadSummary = content.threadSummary != nil
        }
        return ReplyRoute.route(
            composerThreadRoot: focusedThreadId,
            targetEventId: target.eventOrTransactionId.id,
            targetThreadRoot: threadRoot,
            targetHasThreadSummary: hasThreadSummary
        )
    }

    /// Sends a text message from this timeline's composer.
    ///
    /// - Parameters:
    ///   - msg: the message content.
    ///   - target: the reply target, or nil for a message that is no reply.
    /// - Returns: false if this timeline is not loaded yet, so nothing was
    ///   sent. True if the send queue has the message.
    func send(
        _ msg: RoomMessageEventContentWithoutRelation,
        replyingTo target: MatrixRustSDK.EventTimelineItem?
    ) async throws -> Bool {
        let route = target.map { replyRoute(to: $0) }
        guard let sendTimeline = try await sdkTimeline(for: route) else { return false }
        if let inReplyTo = route?.inReplyTo {
            try await sendTimeline.sendReply(msg: msg, eventId: inReplyTo)
        } else {
            _ = try await sendTimeline.send(msg: msg)
        }
        return true
    }

    /// The SDK timeline that must send a message with this route.
    ///
    /// - Parameter route: the reply route, or nil for a message that is not
    ///   a reply.
    /// - Returns: this timeline's SDK timeline if its focus is the route's
    ///   destination, or a timeline with the focus on the route's thread.
    ///   `threadReplies` keeps that thread timeline and listens to it, so
    ///   the main column can show a send that failed (MATRIX-173). Nil if
    ///   this timeline is not loaded yet.
    func sdkTimeline(for route: ReplyRoute?) async throws -> Timeline? {
        guard let threadRoot = route?.threadRoot, threadRoot != focusedThreadId else {
            return timeline
        }
        return try await threadReplies.timeline(forThread: threadRoot)
    }
}

extension LiveTimeline {
    /// The configuration of every timeline this class builds: the one it
    /// shows, and the thread timelines of `ThreadReplyWatch`.
    static func configuration(focus: TimelineFocus) -> TimelineConfiguration {
        TimelineConfiguration(
            focus: focus,
            filter: .all,
            internalIdPrefix: nil,
            dateDividerMode: .daily,
            trackReadReceipts: .allEvents,
            // Forward this timeline's UTDs to the client's delegate
            // (`UtdReporter`), so a failure to decrypt is recorded with the
            // cause the crypto layer assigns it instead of being silent.
            reportUtds: true
        )
    }
}

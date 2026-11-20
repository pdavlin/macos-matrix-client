import Foundation
import MatrixRustSDK
import Models

/// Applies `Models.ReplyRoute` to the SDK (MATRIX-169).
///
/// The pinned SDK (26.11.11) has no reply parameters on the FFI: `Timeline`
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
///
/// MATRIX-216: a reply that the main timeline sends to a message with no
/// thread relation is a plain reply (`m.in_reply_to` only). The route must
/// send a reply for a new thread through a thread timeline, also before
/// the thread has its first reply.
public extension LiveTimeline {
    /// The route of a reply to `target` from this timeline's composer.
    ///
    /// - Parameter openThreadRoot: the root of the thread that the window's
    ///   thread panel shows in this room, or nil.
    func replyRoute(to target: MatrixRustSDK.EventTimelineItem, openThreadRoot: String?) -> ReplyRoute {
        ReplyRoute.route(
            composerThreadRoot: focusedThreadId,
            openThreadRoot: openThreadRoot,
            targetEventId: target.eventOrTransactionId.id,
            targetContent: target.content
        )
    }

    /// Sends a text message from this timeline's composer.
    ///
    /// - Parameters:
    ///   - msg: the message content.
    ///   - target: the reply target, or nil for a message that is no reply.
    ///   - openThreadRoot: the root of the thread that the window's thread
    ///     panel shows in this room, or nil.
    /// - Returns: false if this timeline is not loaded yet, so nothing was
    ///   sent. True if the send queue has the message.
    func send(
        _ msg: RoomMessageEventContentWithoutRelation,
        replyingTo target: MatrixRustSDK.EventTimelineItem?,
        openThreadRoot: String?
    ) async throws -> Bool {
        let route = target.map { replyRoute(to: $0, openThreadRoot: openThreadRoot) }
        guard let sendTimeline = try await sdkTimeline(for: route) else { return false }
        if let inReplyTo = route?.inReplyTo {
            _ = try await sendTimeline.sendReply(msg: msg, eventId: inReplyTo)
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
        switch ReplyRoute.sendTimeline(for: route, composerThreadRoot: focusedThreadId) {
        case .composer:
            return timeline
        case let .thread(root):
            return try await threadReplies.timeline(forThread: root)
        }
    }
}

extension ReplyRoute {
    /// The route of a reply to a timeline item with `targetContent`
    /// (MATRIX-216).
    ///
    /// Only the thread facts of a message-like item count: its thread root,
    /// and a thread summary with at least one reply (`ThreadRootRule`). The
    /// kind of message (text, image, any other) does not. The SDK gives a
    /// summary with no reply to a message whose thread timeline is open
    /// before its first reply, so that summary alone makes no thread root.
    static func route(
        composerThreadRoot: String?,
        openThreadRoot: String?,
        targetEventId: String,
        targetContent: MatrixRustSDK.TimelineItemContent
    ) -> ReplyRoute {
        var threadRoot: String?
        var isThreadRoot = false
        if case let .msgLike(content: content) = targetContent {
            threadRoot = content.threadRoot
            isThreadRoot = ThreadRootRule.isThreadRoot(replyCount: content.threadSummary?.numReplies())
        }
        return route(
            composerThreadRoot: composerThreadRoot,
            openThreadRoot: openThreadRoot,
            targetEventId: targetEventId,
            targetThreadRoot: threadRoot,
            targetHasThreadSummary: isThreadRoot
        )
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

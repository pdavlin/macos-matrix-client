import Core
import MatrixRustSDK
import OSLog

/// The composer's target for a live room or thread (MATRIX-86, MATRIX-245).
///
/// It makes the calls the Mac `ChatInputView` makes, and no others: the body
/// goes through `messageEventContentFromMarkdown`, then the shared
/// `LiveTimeline.send(_:replyingTo:openThreadRoot:)`. The reply target is the
/// shared `LiveTimeline.sendReplyTo`, which the row's Reply action sets.
///
/// MATRIX-246: the shared route (`Models.ReplyRoute`) picks the destination,
/// as on the Mac (MATRIX-232). A reply in a room whose network puts every
/// reply in a thread (`ThreadedReplyRule`), or a reply to a thread root,
/// goes into the thread of its target through a thread-focused SDK
/// timeline. Any other reply from the room timeline is a plain reply. On a
/// thread timeline every message goes into its thread.
@MainActor
final class LiveComposerTarget: ComposerTarget {
    struct TimelineNotReadyError: Error {}

    /// The `openThreadRoot` that the composer gives the shared route: always
    /// nil. The Mac passes the thread its panel shows beside the room
    /// (MATRIX-216). On iOS the thread screen covers the room, so the room
    /// composer is never on screen with a thread, and the thread screen's
    /// own composer has the thread as its focus.
    nonisolated static let openThreadRoot: String? = nil

    let timeline: LiveTimeline

    init(timeline: LiveTimeline) {
        self.timeline = timeline
    }

    var reply: ComposerReply? {
        timeline.sendReplyTo.map { item in
            ComposerReply(
                id: item.eventOrTransactionId.id,
                senderName: item.fingerprintSenderName,
                preview: item.content.description
            )
        }
    }

    func cancelReply() {
        timeline.sendReplyTo = nil
    }

    func send(body: String) async throws {
        let msg = messageEventContentFromMarkdown(md: body)
        guard try await timeline.send(msg, replyingTo: timeline.sendReplyTo, openThreadRoot: Self.openThreadRoot) else {
            throw TimelineNotReadyError()
        }
        // Enqueued: the send queue owns it from here.
        timeline.requestScrollToBottom()
    }

    func noteTyping() async {
        do {
            try await timeline.room.room.typingNotice(isTyping: true)
        } catch {
            Logger.composerIOS.warning("failed to send typing notice: \(error)")
        }
    }
}

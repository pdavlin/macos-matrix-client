import Core
import MatrixRustSDK
import OSLog

/// The composer's target for a live room (MATRIX-86).
///
/// It makes the calls the Mac `ChatInputView` makes, and no others: the body
/// goes through `messageEventContentFromMarkdown`, then `Timeline.send` or
/// `Timeline.sendReply`. The reply target is the shared
/// `LiveTimeline.sendReplyTo`, which the row's Reply action sets.
@MainActor
final class LiveComposerTarget: ComposerTarget {
    struct TimelineNotReadyError: Error {}

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
        guard let innerTimeline = timeline.timeline else { throw TimelineNotReadyError() }
        let msg = messageEventContentFromMarkdown(md: body)
        if let replyTo = timeline.sendReplyTo {
            _ = try await innerTimeline.sendReply(msg: msg, eventId: replyTo.eventOrTransactionId.id)
        } else {
            _ = try await innerTimeline.send(msg: msg)
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

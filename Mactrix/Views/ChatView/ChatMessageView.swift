import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import Tokens
import UI

struct ChatMessageView: View, UI.MessageEventActions {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @AppStorage(TypographyToken.fontSizeStorageKey) private var fontSize = TypographyToken.defaultBaseFontSize

    let timeline: LiveTimeline?
    let event: MatrixRustSDK.EventTimelineItem
    let msg: MatrixRustSDK.MsgLikeContent
    let includeProfileHeader: Bool

    var name: String {
        if case let .ready(displayName, _, _) = event.senderProfileDetails, let displayName = displayName {
            return displayName
        }
        return event.sender
    }

    func toggleReaction(key: String) {
        Task {
            guard let innerTimeline = timeline?.timeline else { return }
            do {
                let reactionWasAdded = try await innerTimeline.toggleReaction(itemId: event.eventOrTransactionId, key: key)
                Logger.viewCycle.debug("reaction \(reactionWasAdded ? "added" : "removed"): \(key)")
            } catch {
                Logger.viewCycle.error("Failed to toggle reaction: \(error)")
            }
        }
    }

    func reply() {
        Logger.viewCycle.info("Reply to event: \(event.eventOrTransactionId.id)")
        timeline?.sendReplyTo = event
    }

    func replyInThread() {
        windowState.focusThread(rootEventId: event.eventOrTransactionId.id)
    }

    func pin() {
        Logger.viewCycle.info("Pinning message")
        guard case let .eventId(eventId: eventId) = event.eventOrTransactionId else { return }
        Task {
            do {
                _ = try await timeline?.timeline?.pinEvent(eventId: eventId)
            } catch {
                Logger.viewCycle.error("Failed to ping message: \(error)")
            }
        }
    }

    func focusUser() {
        Logger.viewCycle.info("Focusing user \(event.sender)")
        windowState.focusUser(userId: event.sender)
    }

    /// Retries a failed local echo. The SDK owns retry semantics: a
    /// recoverable failure disabled the room's send queue, so retry re-enables
    /// it and the queue resends on its own; an unrecoverable failure wedged
    /// this event, so retry unwedges it through its send handle.
    func retrySend(isRecoverable: Bool) {
        Task {
            if isRecoverable {
                timeline?.room.room.enableSendQueue(enable: true)
                Logger.viewCycle.info("re-enabled send queue to retry \(event.eventOrTransactionId.id)")
                return
            }
            guard let handle = event.lazyProvider.getSendHandle() else {
                Logger.viewCycle.error("retrySend: no send handle for \(event.eventOrTransactionId.id)")
                return
            }
            do {
                try await handle.tryResend()
                Logger.viewCycle.info("resend requested for \(event.eventOrTransactionId.id)")
            } catch {
                Logger.viewCycle.error("failed to resend \(event.eventOrTransactionId.id): \(error)")
            }
        }
    }

    /// Discards a failed local echo by aborting it in the send queue.
    func discardFailedSend() {
        Task {
            guard let handle = event.lazyProvider.getSendHandle() else {
                Logger.viewCycle.error("discardFailedSend: no send handle for \(event.eventOrTransactionId.id)")
                return
            }
            do {
                let aborted = try await handle.abort()
                Logger.viewCycle.info("abort of \(event.eventOrTransactionId.id) returned \(aborted)")
            } catch {
                Logger.viewCycle.error("failed to abort \(event.eventOrTransactionId.id): \(error)")
            }
        }
    }

    @ViewBuilder
    var message: some View {
        switch msg.kind {
        case let .message(content: content):
            switch content.msgType {
            case let .emote(content: content):
                Text("Emote: \(content.body)").textSelection(.enabled)
            case let .image(content: content):
                MessageImageView(content: content)
            case let .audio(content: content):
                MessageAudioView(content: content)
            case let .video(content: content):
                MessageVideoView(content: content)
            case let .file(content: content):
                MessageFileView(content: content)
            case let .gallery(content: content):
                Text("Gallery: \(content.body)").textSelection(.enabled)
            case let .notice(content: content):
                Text(content.body.formatAsMarkdown)
                    .textSelection(.enabled)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case let .text(content: content):
                FormattedBodyView(messageContent: content)
            // Text(content.body.formatAsMarkdown)
            case let .location(content: content):
                Text("Location: \(content.body) \(content.geoUri)").textSelection(.enabled)
            case let .other(msgtype: msgtype, body: body):
                Text("Other: \(msgtype) \(body)").textSelection(.enabled)
            }
        case .sticker(body: let body, info: _, source: _):
            Text("Sticker: \(body)").textSelection(.enabled)
        case .poll(question: let question, kind: _, maxSelections: _, answers: _, votes: _, endTime: _, hasBeenEdited: _):
            Text("Poll: \(question)").textSelection(.enabled)
        case .redacted:
            Text("Message redacted")
                .italic()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case .unableToDecrypt:
            Text("Unable to decrypt")
                .italic()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case let .other(eventType: eventType):
            let eventText = eventType.description

            Text("Custom event: \(eventText)").textSelection(.enabled)
        case .liveLocation(content: let content):
            Text("Live location: \(content.description ?? "no description")")
        }
    }

    var isEventFocused: Bool {
        return timeline?.focusedTimelineEventId == event.eventOrTransactionId
    }

    var ownUserId: String {
        do {
            return try appState.matrixClient?.client.userId() ?? ""
        } catch {
            Logger.viewCycle.error("failed to get user id for message \(error)")
            return ""
        }
    }

    var typography: TimelineTypography {
        TimelineTypography(base: CGFloat(fontSize))
    }

    var body: some View {
        if includeProfileHeader {
            UI.MessageEventProfileView(event: event, actions: self, imageLoader: appState.matrixClient)
                .font(.system(size: typography.base))
        }
        UI.MessageEventBodyView(event: event, focused: isEventFocused, reactions: msg.reactions, actions: self, ownUserID: ownUserId, imageLoader: appState.matrixClient, roomMembers: timeline?.room.members ?? []) {
            VStack(alignment: .leading, spacing: 10) {
                if let replyTo = msg.inReplyTo {
                    let eventId = replyTo.eventId()
                    let embeddedEvent = timeline?.loadedReplyDetails[eventId]?.event() ?? replyTo.event()
                    EmbeddedMessageView(embeddedEvent: embeddedEvent) {
                        timeline?.focusEvent(id: .eventId(eventId: eventId))
                    }
                    .padding(.bottom, 10)
                }

                message

                if case let .sendingFailed(message: failureMessage, isRecoverable: isRecoverable) = event.sendState {
                    UI.MessageSendFailureView(
                        message: failureMessage,
                        retry: { retrySend(isRecoverable: isRecoverable) },
                        discard: { discardFailedSend() }
                    )
                }

                if let threadSummary = msg.threadSummary {
                    MessageThreadSummary(summary: threadSummary) {
                        windowState.focusThread(rootEventId: event.eventOrTransactionId.id)
                    }
                }
            }
        }
        .font(.system(size: typography.base))
        .environment(\.timelineTypography, typography)
    }
}

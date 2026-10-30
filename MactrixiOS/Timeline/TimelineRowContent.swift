import Core
import MatrixRustSDK
import MessageFormatting
import Models
import OSLog
import SwiftUI
import Tokens
import UI
import UIKit

/// What every row view needs besides its row model (MATRIX-85).
///
/// One value for the cell and the offscreen measurement alike, so a measured
/// height is the height the row draws at.
struct TimelineRowContext {
    /// The live timeline behind SDK rows. Nil for the DEBUG fixture.
    let timeline: LiveTimeline?
    let imageLoader: (any UI.ImageLoader)?
    let ownUserId: String
    /// D-3: receipts render in direct rooms only.
    let showsReadReceipts: Bool
    let typography: TimelineTypography
    let retryPagination: () -> Void
    /// Fetches previews and files for media rows (MATRIX-86).
    var media: (any TimelineMediaLoading)?
    /// Presents the full-screen viewer for a downloaded file.
    var openMedia: (MediaViewerItem) -> Void = { _ in }
    /// Actions for rows whose event is not an SDK event: the DEBUG fixture.
    /// SDK rows act through the live timeline instead.
    var fallbackActions: (any TimelineFallbackRowActions)?
}

/// Reply and send-failure actions for non-SDK rows, keyed by row id.
@MainActor
protocol TimelineFallbackRowActions {
    func reply(toRow rowId: String)
    func retrySend(ofRow rowId: String)
    func discardSend(ofRow rowId: String)
}

/// The SwiftUI view one timeline row renders, in a cell and in the offscreen
/// measurement (MATRIX-85). The iOS twin of the Mac `TimelineItemRowView`,
/// built from the same shared row views in `UI`.
struct TimelineRowContent: View {
    let row: TimelineRow
    /// From `TimelineSenderGrouping`: whether this message opens a sender run.
    let showsSenderHeader: Bool
    let context: TimelineRowContext

    var body: some View {
        content
            .font(.system(size: context.typography.base))
            .environment(\.timelineTypography, context.typography)
            .environment(\.timelineShowsReadReceipts, context.showsReadReceipts)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch row {
        case let .message(uniqueId, event, _, _):
            if let event = event as? MatrixRustSDK.EventTimelineItem, case let .msgLike(content: msgLike) = event.content {
                TimelineMessageRow(event: event, msgLike: msgLike, showsSenderHeader: showsSenderHeader, context: context)
            } else {
                fallbackMessage(event, rowId: uniqueId)
            }
        case let .state(_, event, name):
            if let event = event as? MatrixRustSDK.EventTimelineItem {
                UI.GenericEventView(event: event, name: name)
            } else {
                Text(name)
            }
        case let .virtual(_, item):
            UI.VirtualItemView(item: item)
        case let .typingIndicator(_, names):
            UI.TypingIndicatorRow(names: names)
        case .paginationActivity:
            UI.PaginationActivityRow()
        case let .paginationFailure(_, message):
            UI.PaginationFailureRow(message: message, retry: context.retryPagination)
        case .unsupported:
            // The measurement clamps an empty row to 1pt, as on the Mac.
            EmptyView()
        }
    }

    /// A message row whose event is not an SDK event: the DEBUG fixture. It
    /// draws through the same shared header, body, reply, media, and failure
    /// views as a real row.
    ///
    /// Type-erased because the row holds its event as an existential; only
    /// fixture rows take this path.
    private func fallbackMessage(_ event: some Models.EventTimelineItem, rowId: String) -> AnyView {
        let textEvent = event as? any TimelineTextEvent
        let actions = context.fallbackActions
        return AnyView(VStack(spacing: 0) {
            if showsSenderHeader {
                UI.MessageEventProfileView(event: event, actions: TimelineNoActions(), imageLoader: nil)
            }
            UI.MessageEventBodyView(
                event: event,
                focused: false,
                reactions: textEvent?.reactionPills ?? [],
                actions: TimelineNoActions(),
                ownUserID: context.ownUserId,
                imageLoader: nil,
                roomMembers: [MockRoomMember]()
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if let quoted = textEvent?.quotedReply {
                        UI.MessageReplyView(username: quoted.senderName, message: quoted.preview)
                            .padding(.bottom, 10)
                    }
                    if let media = textEvent?.media {
                        TimelineMediaView(media: media, context: context)
                    } else {
                        TimelineFormattedText(text: textEvent?.body ?? "", html: textEvent?.formattedBody)
                    }
                    if case let .sendingFailed(message, _) = event.sendState {
                        UI.MessageSendFailureView(
                            message: message,
                            retry: { actions?.retrySend(ofRow: rowId) },
                            discard: { actions?.discardSend(ofRow: rowId) }
                        )
                    }
                }
            }
        }
        .contextMenu {
            if event.canBeRepliedTo {
                Button("Reply", systemImage: "arrowshape.turn.up.left") {
                    actions?.reply(toRow: rowId)
                }
            }
            if let body = textEvent?.body, !body.isEmpty, textEvent?.media == nil {
                TimelineCopyButton(text: body)
            }
        })
    }
}

/// An event that carries its own body text and reaction pills. Only the DEBUG
/// fixture conforms; SDK rows render from SDK content.
protocol TimelineTextEvent: Models.EventTimelineItem {
    var body: String { get }
    /// An HTML body, rendered instead of `body` as SDK text is.
    var formattedBody: String? { get }
    /// Media drawn instead of the text.
    var media: TimelineMedia? { get }
    /// The message this one replies to, as its preview draws it.
    var quotedReply: ComposerReply? { get }
    var reactionPills: [TimelineReactionPill] { get }
}

/// A reaction pill reduced to its key and tally, for non-SDK rows.
struct TimelineReactionPill: Models.Reaction {
    struct Sender: Models.ReactionSenderData {
        let senderId: String
        let date: Date
    }

    let key: String
    let senders: [Sender]

    var id: String { key }
}

/// Message actions for rows that take none from the shared views. Reactions,
/// pins, and threads are outside the iOS fence (E-APP-05 §8).
struct TimelineNoActions: UI.MessageEventActions {
    func toggleReaction(key _: String) {}
    func reply() {}
    func replyInThread() {}
    func pin() {}
    func focusUser() {}
}

/// One SDK message row: the shared profile header and body views around an
/// iOS message body, with the send-failure surface and the context menu.
private struct TimelineMessageRow: View, UI.MessageEventActions {
    let event: MatrixRustSDK.EventTimelineItem
    let msgLike: MatrixRustSDK.MsgLikeContent
    let showsSenderHeader: Bool
    let context: TimelineRowContext

    func toggleReaction(key _: String) {}

    func reply() {
        Logger.timelineIOS.info("reply target set: \(event.eventOrTransactionId.id, privacy: .public)")
        context.timeline?.sendReplyTo = event
    }

    func replyInThread() {}
    func pin() {}
    func focusUser() {}

    /// Retries a failed local echo, as the Mac `ChatMessageView` does: a
    /// recoverable failure disabled the room's send queue, so retry re-enables
    /// it; an unrecoverable one wedged this event, so its send handle resends.
    private func retrySend(isRecoverable: Bool) {
        let event = event
        let room = context.timeline?.room.room
        Task {
            if isRecoverable {
                room?.enableSendQueue(enable: true)
                Logger.timelineIOS.info("re-enabled send queue to retry \(event.eventOrTransactionId.id, privacy: .public)")
                return
            }
            guard let handle = event.lazyProvider.getSendHandle() else {
                Logger.timelineIOS.error("retrySend: no send handle for \(event.eventOrTransactionId.id, privacy: .public)")
                return
            }
            do {
                try await handle.tryResend()
            } catch {
                Logger.timelineIOS.error("failed to resend \(event.eventOrTransactionId.id, privacy: .public): \(error)")
            }
        }
    }

    /// Discards a failed local echo by aborting it in the send queue.
    private func discardFailedSend() {
        let event = event
        Task {
            guard let handle = event.lazyProvider.getSendHandle() else {
                Logger.timelineIOS.error("discardFailedSend: no send handle for \(event.eventOrTransactionId.id, privacy: .public)")
                return
            }
            do {
                _ = try await handle.abort()
            } catch {
                Logger.timelineIOS.error("failed to abort \(event.eventOrTransactionId.id, privacy: .public): \(error)")
            }
        }
    }

    private var isFocused: Bool {
        context.timeline?.focusedTimelineEventId == event.eventOrTransactionId
    }

    /// The plain text Copy puts on the pasteboard, or nil for media and
    /// non-message rows.
    private var copyableText: String? {
        guard case let .message(content) = msgLike.kind, TimelineMedia(content.msgType) == nil else { return nil }
        return content.body
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsSenderHeader {
                UI.MessageEventProfileView(event: event, actions: self, imageLoader: context.imageLoader)
            }
            UI.MessageEventBodyView(
                event: event,
                focused: isFocused,
                reactions: msgLike.reactions,
                actions: self,
                ownUserID: context.ownUserId,
                imageLoader: context.imageLoader,
                roomMembers: context.timeline?.room.members ?? []
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if let replyTo = msgLike.inReplyTo {
                        replyPreview(replyTo)
                    }
                    TimelineMessageBody(kind: msgLike.kind, context: context)
                    if case let .sendingFailed(message, isRecoverable) = event.sendState {
                        UI.MessageSendFailureView(
                            message: message,
                            retry: { retrySend(isRecoverable: isRecoverable) },
                            discard: { discardFailedSend() }
                        )
                    }
                }
            }
        }
        .contextMenu {
            if event.canBeRepliedTo {
                Button("Reply", systemImage: "arrowshape.turn.up.left") {
                    reply()
                }
            }
            if let copyableText {
                TimelineCopyButton(text: copyableText)
            }
        }
    }

    @ViewBuilder
    private func replyPreview(_ replyTo: MatrixRustSDK.InReplyToDetails) -> some View {
        let eventId = replyTo.eventId()
        let embedded = context.timeline?.loadedReplyDetails[eventId]?.event() ?? replyTo.event()
        Group {
            switch embedded {
            case .unavailable, .pending:
                UI.MessageReplyView(username: "Loading", message: "Loading reply")
                    .redacted(reason: .placeholder)
            case let .ready(content, sender, senderProfile, _, _):
                UI.MessageReplyView(
                    username: {
                        if case let .ready(name, _, _) = senderProfile, let name { return name }
                        return sender
                    }(),
                    message: content.description
                ) {
                    context.timeline?.focusEvent(id: .eventId(eventId: eventId))
                }
            case let .error(message):
                Text("Reply unavailable: \(message)")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 10)
    }
}

/// The Copy action of a message's context menu.
struct TimelineCopyButton: View {
    let text: String

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = text
        }
    }
}

/// A text body: the HTML formatted body through `MessageFormatting` when the
/// event has one, the raw body otherwise. The Mac `FormattedBodyView` rule:
/// formatted is used when its format is HTML (MATRIX-86).
///
/// Text is not selectable: a long press opens the message's context menu,
/// which carries Copy. The formatted view keeps its own selection, so its
/// links stay tappable.
struct TimelineFormattedText: View {
    let text: String
    let html: String?

    @Environment(\.timelineTypography) private var typography

    var body: some View {
        if let html {
            AttributedTextView(attributedString: parseFormattedBody(html, baseFontSize: typography.base))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The body of an SDK message on iOS: formatted text, media, or a one-line
/// label for kinds outside the M1 read path.
private struct TimelineMessageBody: View {
    let kind: MatrixRustSDK.MsgLikeKind
    let context: TimelineRowContext

    var body: some View {
        switch kind {
        case let .message(content: content):
            VStack(alignment: .leading, spacing: 2) {
                messageType(content.msgType)
                if content.isEdited {
                    UI.EditedMarker()
                }
            }
        case let .sticker(body, _, _):
            label("Sticker", body)
        case let .poll(question, _, _, _, _, _, _):
            label("Poll", question)
        case .redacted:
            Text("Message redacted")
                .italic()
                .foregroundStyle(.secondary)
        case let .unableToDecrypt(msg: encrypted):
            UI.UnableToDecryptView(cause: Models.UnableToDecryptCause(encrypted: encrypted))
        case let .other(eventType):
            label("Custom event", eventType.description)
        case let .liveLocation(content):
            label("Live location", content.description ?? "no description")
        }
    }

    @ViewBuilder
    private func messageType(_ type: MatrixRustSDK.MessageType) -> some View {
        switch type {
        case let .text(content):
            TimelineFormattedText(
                text: content.body,
                html: content.formatted?.format == .html ? content.formatted?.body : nil
            )
        case let .notice(content):
            wrapped(content.body)
                .foregroundStyle(.secondary)
        case let .emote(content):
            wrapped("* \(content.body)")
        case .image, .video, .audio, .file:
            if let media = TimelineMedia(type) {
                TimelineMediaView(media: media, context: context)
            }
        case let .gallery(content):
            label("Gallery", content.body)
        case let .location(content):
            label("Location", content.body)
        case let .other(msgtype, body):
            label(msgtype, body)
        }
    }

    private func wrapped(_ text: String) -> some View {
        Text(text.formatAsMarkdown)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func label(_ title: String, _ detail: String) -> some View {
        Text("\(title): \(detail)")
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

extension Logger {
    static let timelineIOS = Logger(subsystem: "io.davlin.matrixclient.ios", category: "timeline")
}

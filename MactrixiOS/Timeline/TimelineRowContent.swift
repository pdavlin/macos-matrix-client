import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import Tokens
import UI

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
        case let .message(_, event, _, _):
            if let event = event as? MatrixRustSDK.EventTimelineItem, case let .msgLike(content: msgLike) = event.content {
                TimelineMessageRow(event: event, msgLike: msgLike, showsSenderHeader: showsSenderHeader, context: context)
            } else {
                fallbackMessage(event)
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
    /// draws through the same shared header and body views as a real row.
    ///
    /// Type-erased because the row holds its event as an existential; only
    /// fixture rows take this path.
    private func fallbackMessage(_ event: some Models.EventTimelineItem) -> AnyView {
        AnyView(VStack(spacing: 0) {
            if showsSenderHeader {
                UI.MessageEventProfileView(event: event, actions: TimelineNoActions(), imageLoader: nil)
            }
            UI.MessageEventBodyView(
                event: event,
                focused: false,
                reactions: (event as? any TimelineTextEvent)?.reactionPills ?? [],
                actions: TimelineNoActions(),
                ownUserID: context.ownUserId,
                imageLoader: nil,
                roomMembers: [MockRoomMember]()
            ) {
                Text((event as? any TimelineTextEvent)?.body ?? "")
                    .fixedSize(horizontal: false, vertical: true)
            }
        })
    }
}

/// An event that carries its own body text and reaction pills. Only the DEBUG
/// fixture conforms; SDK rows render from SDK content.
protocol TimelineTextEvent: Models.EventTimelineItem {
    var body: String { get }
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

/// Message actions for the iOS read path. Reply sets the composer's target
/// (MATRIX-86 reads `sendReplyTo`). Reactions, pins, and threads are outside
/// the iOS fence (E-APP-05 §8), so those actions do nothing here.
struct TimelineNoActions: UI.MessageEventActions {
    func toggleReaction(key _: String) {}
    func reply() {}
    func replyInThread() {}
    func pin() {}
    func focusUser() {}
}

/// One SDK message row: the shared profile header and body views around an
/// iOS message body.
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

    private var isFocused: Bool {
        context.timeline?.focusedTimelineEventId == event.eventOrTransactionId
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
                    TimelineMessageBody(kind: msgLike.kind)
                }
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

/// The body of an SDK message on iOS.
///
/// Text renders as plain text: the formatted-HTML path (`MessageFormatting`)
/// and the media views arrive with MATRIX-86. Media rows show a one-line
/// label until then, so their height is stable and fingerprinted like text.
private struct TimelineMessageBody: View {
    let kind: MatrixRustSDK.MsgLikeKind

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
            wrapped(content.body)
        case let .notice(content):
            wrapped(content.body)
                .foregroundStyle(.secondary)
        case let .emote(content):
            wrapped("* \(content.body)")
        case let .image(content):
            label("Image", content.filename)
        case let .video(content):
            label("Video", content.filename)
        case let .audio(content):
            label("Audio", content.filename)
        case let .file(content):
            label("File", content.filename)
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
            .textSelection(.enabled)
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

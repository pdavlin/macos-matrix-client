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
    /// The account's global profile avatar (MATRIX-163). An own message
    /// without a room member avatar draws it.
    var ownAvatarUrl: String?
    /// Whether every reply in the room belongs in a thread (MATRIX-232,
    /// `LiveTimeline.repliesInThreads`): the long-press menu then offers
    /// Reply in Thread in place of Reply (MATRIX-246). The container reads
    /// it once for all rows. It changes no row height.
    var repliesInThreads = false
    /// Pushes the thread screen (MATRIX-245): a tap on a thread chip, or
    /// "Reply in Thread" in the room timeline. A no-op where no thread can
    /// open: the thread screen itself, and the DEBUG fixture.
    var openThread: @MainActor (ThreadScreenRequest) -> Void = { _ in }
    /// Puts the keyboard focus in the composer under the timeline: "Reply in
    /// Thread" in the thread screen (MATRIX-245).
    var focusComposer: @MainActor () -> Void = {}
    /// The client that ranks the quick reactions and records a reaction use
    /// (MATRIX-249, MATRIX-262). Nil for the DEBUG fixture.
    var client: MatrixClient?
    /// Shows the reaction picker sheet on a message: "Add Reaction…" in the
    /// long-press menu (MATRIX-249).
    var openReactionPicker: @MainActor (TimelineReactionPickerRequest) -> Void = { _ in }
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
            .environment(\.ownAccountAvatarUrl, context.ownAvatarUrl)
            .environment(\.reactionEmojiName, context.reactionEmojiName)
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
                        TimelineFormattedText(
                            text: textEvent?.body ?? "",
                            html: textEvent?.formattedBody,
                            imageLoader: context.imageLoader
                        )
                    }
                    if case let .sendingFailed(message, _) = event.sendState {
                        UI.MessageSendFailureView(
                            message: message,
                            retry: { actions?.retrySend(ofRow: rowId) },
                            discard: { actions?.discardSend(ofRow: rowId) }
                        )
                    }
                    if let summary = Self.chipSummary(of: textEvent, rowId: rowId) {
                        UI.MessageThreadSummary(summary: summary, imageLoader: context.imageLoader) {
                            context.openThread(.chip(rootEventId: rowId))
                        }
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

    /// The thread summary that a non-SDK row's chip draws, or nil
    /// (MATRIX-245): the rule of the SDK row, in a room timeline.
    private static func chipSummary(of event: (any TimelineTextEvent)?, rowId: String) -> (any Models.ThreadSummary)? {
        guard let summary = event?.threadSummary,
              ThreadRootRule.showsChip(replyCount: summary.numReplies(), rowEventId: rowId, timelineThreadRoot: nil)
        else { return nil }
        return summary
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
    /// The thread summary the row's chip draws, or nil (MATRIX-245).
    var threadSummary: (any Models.ThreadSummary)? { get }
}

extension TimelineTextEvent {
    /// The fixture and the gate rows have no thread.
    var threadSummary: (any Models.ThreadSummary)? { nil }
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

/// Message actions for rows that take none from the shared views: the DEBUG
/// fixture and the timeline gate. Pins are outside the iOS fence (E-APP-05
/// §8). SDK rows take reactions (MATRIX-249).
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

    /// A chip tap, and the chip's long-press menu (MATRIX-249).
    func toggleReaction(key: String) {
        context.toggleReaction(key: key, on: event.eventOrTransactionId)
    }

    /// Runs one action of the long-press menu: the reply entries and the
    /// reaction entries (MATRIX-249).
    func perform(_ action: MessageAction) {
        switch action {
        case .reply: reply()
        case .replyInThread: replyInThread()
        case let .toggleReaction(key): toggleReaction(key: key)
        case .openReactionPicker: context.openReactionPicker(TimelineReactionPickerRequest(itemId: event.eventOrTransactionId))
        case .pin, .edit, .forward, .copyText, .copyLink, .unpin, .quickLook, .playInline, .saveToDownloads, .redact,
             .copyMessages, .openOriginalLink, .copyOriginalLink, .bookmark, .removeBookmark, .showEditHistory:
            break
        }
    }

    func reply() {
        Logger.timelineIOS.info("reply target set: \(event.eventOrTransactionId.id, privacy: .public)")
        context.timeline?.sendReplyTo = event
    }

    /// "Reply in Thread" (MATRIX-245): the room timeline pushes the thread
    /// screen with the focus in its composer; the thread screen replies in
    /// place. The thread is the one that holds the message, else the
    /// message's own (`ThreadReplyStart`), as on the Mac.
    func replyInThread() {
        let entry = ThreadReplyEntry.of(
            eventId: event.eventOrTransactionId.id,
            messageThreadRoot: msgLike.threadRoot,
            timelineThreadRoot: context.timeline?.focusedThreadId
        )
        switch entry {
        case let .openThread(start):
            Logger.timelineIOS.info("reply in thread: open \(start.root, privacy: .public)")
            context.openThread(.replyInThread(start, to: event))
        case let .replyHere(quotesMessage):
            context.timeline?.sendReplyTo = quotesMessage ? event : nil
            context.focusComposer()
        }
    }

    func pin() {}
    func focusUser() {}

    /// The thread summary the row's chip draws, or nil for no chip
    /// (`ThreadRootRule.showsChip`): the thread screen's own root draws none.
    private var chipThreadSummary: MatrixRustSDK.ThreadSummary? {
        guard let summary = msgLike.threadSummary,
              ThreadRootRule.showsChip(
                  replyCount: summary.numReplies(),
                  rowEventId: event.eventOrTransactionId.id,
                  timelineThreadRoot: context.timeline?.focusedThreadId
              )
        else { return nil }
        return summary
    }

    /// Whether the row is the root of the thread screen that shows it: it
    /// draws the root band (MATRIX-183), as the Mac thread panel's root does.
    private var isThreadScreenRoot: Bool {
        guard let root = context.timeline?.focusedThreadId else { return false }
        return root == event.eventOrTransactionId.id
    }

    /// The message as the shared action model reads it for the long-press
    /// menu. Not `actionSubject`: that one would add the Mac's right-click
    /// menu to the row.
    private var menuSubject: MessageActionSubject {
        var subject = MessageActionSubject(event: event, msg: msgLike, pinnedEventIds: [], redactPermission: .none)
        subject.repliesInThreads = context.repliesInThreads
        return subject
    }

    /// The reply entries of the long-press menu, from the shared action
    /// model (MATRIX-232, MATRIX-245).
    private var replyActions: [MessageAction] {
        TimelineReplyMenu.actions(for: menuSubject, inThread: context.timeline?.focusedThreadId != nil)
    }

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
        // MATRIX-156: a custom emoji tag copies as its ":name:".
        return content.displayBody
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsSenderHeader {
                UI.MessageEventProfileView(event: event, actions: self, imageLoader: context.imageLoader)
            }
            UI.MessageEventBodyView(
                event: event,
                focused: isFocused,
                reactions: event.reactions,
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
                    // MATRIX-245: the Mac chip, under the body. A tap pushes
                    // the thread screen.
                    if let threadSummary = chipThreadSummary {
                        UI.MessageThreadSummary(summary: threadSummary, imageLoader: context.imageLoader) {
                            context.openThread(.chip(rootEventId: event.eventOrTransactionId.id))
                        }
                    }
                }
            }
        }
        .environment(\.timelineRowIsThreadRoot, isThreadScreenRoot)
        .contextMenu {
            // MATRIX-249: the reactions first, as the Mac hover row starts
            // with them.
            TimelineReactionMenuSection(subject: menuSubject, reactions: event.reactions, context: context, perform: perform)
            ForEach(replyActions, id: \.self) { action in
                Button(
                    UI.MessageActionPresentation.title(of: action),
                    systemImage: UI.MessageActionPresentation.systemImage(of: action) ?? "arrowshape.turn.up.left"
                ) {
                    perform(action)
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
                        if case let .ready(name, _, _, _, _) = senderProfile, let name { return name }
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
    /// Loads the custom emoticons of an HTML body (MATRIX-153).
    let imageLoader: (any UI.ImageLoader)?

    @Environment(\.timelineTypography) private var typography

    var body: some View {
        if let html {
            FormattedBodyText(html: html, baseFontSize: typography.base, imageLoader: imageLoader)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension Logger {
    static let timelineIOS = Logger(subsystem: "io.davlin.matrixclient.ios", category: "timeline")
}

import Core
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
    /// The event the reaction picker is open for (MATRIX-111). Keyed by the
    /// event, not a Bool, because the timeline table reuses row views: a
    /// reused row shows another event, and its picker must not stay open.
    @State private var reactionPickerEventKey: String?

    let timeline: LiveTimeline?
    let event: MatrixRustSDK.EventTimelineItem
    let msg: MatrixRustSDK.MsgLikeContent
    /// The row's place in its run (MATRIX-68): whether it draws the profile
    /// header, and the rhythm gap above it.
    let grouping: Models.TimelineRowGrouping

    var name: String {
        if case let .ready(displayName, _, _) = event.senderProfileDetails, let displayName = displayName {
            return displayName
        }
        return event.sender
    }

    /// Toggles the own reaction `key` on this message. Every reaction that
    /// is added, from the hover row, a menu, the picker, or a reaction pill,
    /// counts as a use of the emoji in the account's recent list (D-3).
    /// Removing a reaction is not a use.
    func toggleReaction(key: String) {
        Task {
            guard let innerTimeline = timeline?.timeline else { return }
            do {
                let reactionWasAdded = try await innerTimeline.toggleReaction(itemId: event.eventOrTransactionId, key: key)
                Logger.viewCycle.debug("reaction \(reactionWasAdded ? "added" : "removed"): \(key)")
                if reactionWasAdded {
                    appState.matrixClient?.recordRecentEmoji(key)
                }
            } catch {
                Logger.viewCycle.error("Failed to toggle reaction: \(error)")
            }
        }
    }

    /// The hover row's and the menus' quick reactions: the top three recent
    /// emoji, or the three defaults before the list loads (MATRIX-111).
    var quickReactionKeys: [String] {
        appState.matrixClient?.recentEmojis.quickReactionKeys ?? MessageActionModel.defaultQuickReactionKeys
    }

    /// Opens the reaction picker on this row (MATRIX-111). The recent-emoji
    /// read runs here too, in case no room view started it yet; it is a
    /// no-op once the list has loaded.
    func openReactionPicker() {
        reactionPickerEventKey = event.eventOrTransactionId.id
        Task {
            await appState.matrixClient?.loadRecentEmojisIfNeeded()
        }
    }

    private var isReactionPickerPresented: Binding<Bool> {
        let key = event.eventOrTransactionId.id
        return Binding(
            get: { reactionPickerEventKey == key },
            set: { isPresented in
                if !isPresented, reactionPickerEventKey == key {
                    reactionPickerEventKey = nil
                }
            }
        )
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

    /// The upload indicator state of this row's media, or nil when the row
    /// shows none (MATRIX-107).
    ///
    /// Only an own local echo uploads. The state is read off the SDK send
    /// state the same way the failure banner below reads it; the container
    /// throttles how often a progress tick reaches this view.
    var mediaUploadState: Models.MediaUploadState? {
        event.isOwn ? event.mediaUploadState : nil
    }

    /// Cancels the upload of this local echo. The send queue removes the echo
    /// when the abort lands, so the row goes away on its own.
    func cancelUpload() {
        Task {
            guard let timeline else {
                Logger.viewCycle.error("cancelUpload: no timeline for \(event.eventOrTransactionId.id)")
                return
            }
            let cancelled: Bool = await timeline.cancelMediaSend(localEcho: event)
            Logger.viewCycle.info("cancel of media send \(event.eventOrTransactionId.id) returned \(cancelled)")
        }
    }

    @ViewBuilder
    var message: some View {
        switch msg.kind {
        case let .message(content: content):
            VStack(alignment: .leading, spacing: 2) {
                messageBody(content)
                // Display only: the SDK reports the edit, the app never
                // authors one.
                if content.isEdited {
                    UI.EditedMarker()
                }
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
        case let .unableToDecrypt(msg: encrypted):
            UI.UnableToDecryptView(cause: Models.UnableToDecryptCause(encrypted: encrypted))
        case let .other(eventType: eventType):
            let eventText = eventType.description

            Text("Custom event: \(eventText)").textSelection(.enabled)
        case .liveLocation(content: let content):
            Text("Live location: \(content.description ?? "no description")")
        }
    }

    @ViewBuilder
    private func messageBody(_ content: MatrixRustSDK.MessageContent) -> some View {
        switch content.msgType {
        case let .emote(content: content):
            Text("Emote: \(content.body)").textSelection(.enabled)
        case let .image(content: content):
            MessageImageView(content: content, rowActions: actionTarget)
                .mediaUploadOverlay(mediaUploadState, placement: .mediaCorner, cancel: cancelUpload)
        case let .audio(content: content):
            MessageAudioView(content: content, rowActions: actionTarget)
                .mediaUploadOverlay(mediaUploadState, placement: .rowTrailing, cancel: cancelUpload)
        case let .video(content: content):
            MessageVideoView(content: content, rowActions: actionTarget)
                .mediaUploadOverlay(mediaUploadState, placement: .mediaCorner, cancel: cancelUpload)
        case let .file(content: content):
            MessageFileView(content: content, rowActions: actionTarget)
                .mediaUploadOverlay(mediaUploadState, placement: .rowTrailing, cancel: cancelUpload)
        case let .gallery(content: content):
            Text("Gallery: \(content.body)").textSelection(.enabled)
                .mediaUploadOverlay(mediaUploadState, placement: .rowTrailing, cancel: cancelUpload)
        case let .notice(content: content):
            Text(content.body.formatAsMarkdown)
                .textSelection(.enabled)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case let .text(content: content):
            FormattedBodyView(messageContent: content)
        case let .location(content: content):
            Text("Location: \(content.body) \(content.geoUri)").textSelection(.enabled)
        case let .other(msgtype: msgtype, body: body):
            Text("Other: \(msgtype) \(body)").textSelection(.enabled)
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
        UI.MessageRunRow(grouping: grouping) {
            UI.MessageEventProfileView(event: event, actions: self, imageLoader: appState.matrixClient)
                .font(.system(size: typography.base))
        } message: {
            eventBody
        }
    }

    private var eventBody: some View {
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
        // The picker hangs from the row's top trailing corner, where the
        // hover row's picker button sits. A popover does not change the row
        // height.
        .popover(isPresented: isReactionPickerPresented, attachmentAnchor: .point(.topTrailing), arrowEdge: .top) {
            UI.ReactionPickerView(catalog: .bundled, recents: appState.matrixClient?.recentEmojis.emojis ?? []) { emoji in
                toggleReaction(key: emoji)
            }
        }
        // The Edit menu acts on the hovered or focused message (MATRIX-108).
        // None of these change layout, so the row is not re-measured.
        .onHover { hovering in
            if hovering { offerAsTarget() }
        }
        .onChange(of: isEventFocused) { _, focused in
            if focused { offerAsTarget() }
        }
        .onChange(of: TargetState(
            key: event.eventOrTransactionId.id,
            subject: messageActionSubject,
            quickReactionKeys: quickReactionKeys
        )) { old, _ in
            timeline?.messageActionTarget.refresh(replacing: old.key, with: actionTarget)
        }
        .onDisappear {
            timeline?.messageActionTarget.withdraw(key: event.eventOrTransactionId.id)
        }
    }
}

/// What the Edit-menu target depends on. A change refreshes the target, so
/// the menu does not act on old facts (a local echo that got its event ID, a
/// message that was pinned).
private struct TargetState: Equatable {
    let key: String
    let subject: MessageActionSubject
    let quickReactionKeys: [String]
}

import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import Tokens
import UI

struct ChatInputView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency

    let room: MatrixRustSDK.Room
    let timeline: LiveTimeline
    @Binding var replyTo: MatrixRustSDK.EventTimelineItem?
    /// The merged chat's composer session (MATRIX-143 Phase B), or nil for
    /// a room's composer. With a session, `room` and `timeline` are the
    /// member room the next message goes to, and the session routes the
    /// typing notices, the draft, the edits, and the replies
    /// (`ChatInputView+Merged.swift`).
    var merged: MergedComposerSession?
    @AppStorage(TypographyToken.fontSizeStorageKey) var fontSize = TypographyToken.defaultBaseFontSize

    @State var isDraftLoaded: Bool = false
    /// The composer content as draft text: mention chips are `matrix.to`
    /// pill links (`MentionMarkdown`). The saved draft uses the same text, so
    /// a draft keeps its chips.
    @State var chatInput: String = ""
    @State private var mentions = ComposerMentionController()
    /// The pending attachments (MATRIX-106).
    @State private var attachments = ComposerAttachmentController()
    /// True while a media send waits for its measurements, so a second
    /// Return does not send the same attachments again.
    @State private var isSendingMedia = false
    /// The message the composer edits, or nil when it writes a new message
    /// (MATRIX-109).
    @State var editSession: ComposerEditSession?

    func sendMessage() async {
        if let editSession {
            await saveEdit(editSession)
            return
        }
        if !attachments.isEmpty {
            await sendMedia()
            return
        }
        guard !chatInput.isEmpty else { return }
        guard let innerTimeline = timeline.timeline else { return }

        // MATRIX-105 (D-6): chips become pill links in the markdown, and the
        // mentioned users go into `m.mentions`.
        let outgoing = MentionMarkdown.outgoingMessage(fromDraftText: chatInput)
        let markdownContent = messageEventContentFromMarkdown(md: outgoing.markdown)
        let msg = outgoing.mentionedUserIds.isEmpty
            ? markdownContent
            : markdownContent.withMentions(mentions: MatrixRustSDK.Mentions(userIds: outgoing.mentionedUserIds, room: false))

        do {
            if let replyTo {
                _ = try await innerTimeline.sendReply(msg: msg, eventId: replyTo.eventOrTransactionId.id)
            } else {
                _ = try await innerTimeline.send(msg: msg)
            }
        } catch {
            // The message never reached the send queue, so no local echo will
            // carry a retry affordance. Keep the input so nothing is lost.
            Logger.viewCycle.error("failed to enqueue message: \(error)")
            return
        }

        // Enqueued: the send queue owns it from here. A failure surfaces on
        // the local echo (EventSendState.sendingFailed) with retry/discard.
        chatInput = ""
        replyTo = nil
        scrollToNewestAfterSend()
    }

    /// Sends the pending attachments with the composer text as the caption
    /// and the reply target as `inReplyTo` (MATRIX-106). One attachment goes
    /// by its type, two or more as a gallery (`Models.MediaSendPlan`).
    private func sendMedia() async {
        guard !isSendingMedia else { return }
        isSendingMedia = true
        defer { isSendingMedia = false }

        let measured = await attachments.measuredAttachments()
        guard let request = MediaSendRequest.make(
            attachments: measured,
            draftText: chatInput,
            inReplyTo: replyTo?.eventOrTransactionId.id
        ) else { return }

        do {
            try timeline.sendMedia(request)
        } catch {
            // The send never started, so keep the attachments and the text.
            Logger.viewCycle.error("failed to start media send: \(error)")
            return
        }

        // Started: the send queue owns it. Progress and failure show on the
        // local echo (MATRIX-107).
        attachments.clear()
        chatInput = ""
        replyTo = nil
        scrollToNewestAfterSend()
    }

    private func chatInputChanged() async {
        guard isDraftLoaded else { return } // avoid working on a draft that's being restored
        if let merged {
            // Only to the current target (MATRIX-143).
            merged.composerTextDidChange(isTyping: !chatInput.isEmpty)
        } else if !chatInput.isEmpty {
            do {
                try await room.typingNotice(isTyping: !chatInput.isEmpty)
            } catch {
                Logger.viewCycle.warning("Failed to send typing notice: \(error)")
            }
        }
        await saveDraft()
    }

    /// Gives the mention controller this room's members and the own user id.
    /// The provider reads `LiveRoom.members` on each query, so it sees member
    /// updates without a new SDK call.
    private func configureMentions() {
        let liveRoom = timeline.room
        mentions.candidateProvider = { [weak liveRoom] in
            guard let liveRoom else { return [] }
            return liveRoom.members.map {
                MentionCandidate(userId: $0.userId, displayName: $0.displayName, avatarUrl: $0.avatarUrl)
            }
        }
        if let ownUserId = try? appState.matrixClient?.client.userId() {
            mentions.excludedUserIds = [ownUserId]
        }
    }

    /// Inserts the chip that the user profile "Mention" action asked for,
    /// after the draft has loaded (MATRIX-105).
    private func insertPendingMention() {
        guard isDraftLoaded, let target = timeline.pendingComposerMention else { return }
        timeline.pendingComposerMention = nil
        mentions.insertMention(target)
    }

    /// Whether the composer holds text or attachments.
    private var hasContent: Bool {
        !chatInput.isEmpty || !attachments.isEmpty
    }

    var replyEmbeddedDetails: MatrixRustSDK.EmbeddedEventDetails? {
        guard let replyTo else { return nil }

        return .ready(content: replyTo.content, sender: replyTo.sender, senderProfile: replyTo.senderProfile, timestamp: replyTo.timestamp, eventOrTransactionId: replyTo.eventOrTransactionId)
    }

    var content: some View {
        VStack(alignment: .leading) {
            if let mentionState = mentions.state {
                UI.MentionSuggestionList(
                    suggestions: mentionState.suggestions,
                    selectedIndex: mentionState.selectedIndex,
                    imageLoader: appState.matrixClient,
                    onPick: { mentions.pick($0) }
                )
                Divider()
            }
            if let editSession {
                besideMergedTarget {
                    UI.ComposerEditBar(previewText: ComposerEdit.previewText(fromDraftText: editSession.target.originalDraftText)) {
                        endEdit()
                    }
                }
            }
            if let replyEmbeddedDetails {
                besideMergedTarget {
                    EmbeddedMessageView(embeddedEvent: replyEmbeddedDetails) {
                        replyTo = nil
                    }
                }
            }
            if editSession == nil, replyEmbeddedDetails == nil {
                mergedTargetRow
            }
            // Edit mode keeps the pending attachments for later, out of sight.
            if !attachments.isEmpty, editSession == nil {
                UI.ComposerAttachmentStrip(attachments: attachments.attachments) {
                    attachments.remove($0)
                }
            }
            HStack(alignment: .bottom, spacing: 0) {
                Button {
                    attachments.presentOpenPanel()
                } label: {
                    Image(systemName: "paperclip")
                        .padding(.vertical, DynamicTextView.padding.height)
                        .padding(.leading, DynamicTextView.padding.width)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(!isDraftLoaded || editSession != nil)
                .help("Attach files")
                .accessibilityLabel(Text("Attach files"))
                ChatTextView(
                    text: $chatInput,
                    placeholder: merged?.placeholder ?? "Message \(room.displayName() ?? "room")",
                    disabled: !isDraftLoaded,
                    mentions: mentions,
                    attachments: attachments,
                    attachmentsEnabled: editSession == nil,
                    onEmptyUpArrow: { editLastOwnMessage() },
                    onEscape: { endEdit() },
                    onSubmit: { Task { await sendMessage() } }
                )
            }
        }
        .font(.system(size: .init(fontSize)))
        // Drops on the chips or the paperclip. The text view takes drops on
        // itself (`DynamicTextView.performDragOperation`).
        .dropDestination(for: URL.self) { urls, _ in
            let fileURLs = urls.filter(\.isFileURL)
            guard editSession == nil, !fileURLs.isEmpty else { return false }
            attachments.add(fileURLs: fileURLs)
            return true
        }
        .task(id: ObjectIdentifier(timeline)) {
            configureMentions()
        }
        .onChange(of: timeline.pendingComposerMention, initial: true) {
            insertPendingMention()
        }
        .onChange(of: isDraftLoaded) {
            insertPendingMention()
            startPendingEdit()
        }
        .onChange(of: timeline.pendingComposerEdit, initial: true) {
            startPendingEdit()
        }
        .onChange(of: replyTo?.eventOrTransactionId) {
            leaveEditForReply()
        }
        .task(id: editSession?.target.id) {
            await saveDraft()
        }
        .task(id: chatInput) {
            await chatInputChanged()
        }
        .onChange(of: hasContent, initial: true) { _, newValue in
            // The merged target stays still while the composer has content.
            merged?.composerContentDidChange(hasContent: newValue)
        }
        .task(id: replyTo?.eventOrTransactionId) {
            await saveDraft()
        }
        .task(id: timeline.timeline != nil) {
            // we need the timeline to be populated before we load a draft
            // (in case the draft holds a reply)
            await loadDraft()
        }
    }

    @available(macOS 26.0, *)
    var tahoeView: some View {
        content
            .glassEffect(in: .rect(cornerRadius: 16.0))
            .padding(.horizontal)
            .padding(.bottom, 10)
    }

    var oldView: some View {
        content
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 16.0)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.bottom, 10)
    }

    var body: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            tahoeView
        } else {
            oldView
        }
    }
}

// MARK: - Edit mode (MATRIX-109, M2-B2)

// The draft lives in `ChatInputView+Draft.swift`, the merged chat's parts in
// `ChatInputView+Merged.swift` (MATRIX-143).

/// One edit in the composer: the target, and the draft from before the edit,
/// which comes back when the edit ends.
struct ComposerEditSession {
    let target: MessageEditTarget
    let previousDraftText: String
    let previousReplyTo: MatrixRustSDK.EventTimelineItem?
}

extension ChatInputView {
    /// Puts the composer in edit mode for `target`: the edit bar shows, the
    /// field holds the original text (pills as chips), and the reply and the
    /// draft wait until the edit ends.
    ///
    /// - Parameter owner: The timeline that holds the message. In a merged
    ///   chat the edit goes to its room (MATRIX-143), and the reply from
    ///   before the edit is dropped, because it may belong to another member
    ///   room.
    private func beginEdit(_ target: MessageEditTarget, in owner: LiveTimeline) {
        // A second edit keeps the draft from before the first one.
        let previousDraftText: String = editSession?.previousDraftText ?? chatInput
        let previousReplyTo: MatrixRustSDK.EventTimelineItem? = if merged != nil {
            nil
        } else if let editSession {
            editSession.previousReplyTo
        } else {
            replyTo
        }
        editSession = ComposerEditSession(
            target: target,
            previousDraftText: previousDraftText,
            previousReplyTo: previousReplyTo
        )
        replyTo = nil
        chatInput = target.originalDraftText
        merged?.editDidBegin(in: owner)
        if let textView = mentions.textView {
            unsafe textView.window?.makeFirstResponder(textView)
        }
    }

    /// Leaves edit mode and puts back the draft and the reply from before the
    /// edit. Esc, the x button, and a finished save all end here.
    ///
    /// - Returns: false when the composer was not in edit mode.
    @discardableResult
    private func endEdit() -> Bool {
        guard let session = editSession else { return false }
        editSession = nil
        merged?.editDidEnd()
        chatInput = session.previousDraftText
        replyTo = session.previousReplyTo
        return true
    }

    /// Starts the edit that a message action asked for.
    private func startPendingEdit() {
        guard isDraftLoaded, let target = timeline.pendingComposerEdit else { return }
        timeline.pendingComposerEdit = nil
        beginEdit(target, in: timeline)
    }

    /// The Up arrow in an empty composer: edits the newest own message the
    /// composer can edit.
    ///
    /// - Returns: true if an edit started.
    private func editLastOwnMessage() -> Bool {
        guard isDraftLoaded,
              ComposerEdit.startsEditOnUpArrow(
                  draftText: chatInput,
                  attachmentCount: attachments.attachments.count,
                  isEditing: editSession != nil
              )
        else { return false }
        // A merged chat edits the newest own message of any member room.
        let last: (timeline: LiveTimeline, target: MessageEditTarget)? = if let merged {
            merged.lastEditTarget()
        } else {
            timeline.lastEditTarget().map { (timeline, $0) }
        }
        guard let last else { return false }
        beginEdit(last.target, in: last.timeline)
        return true
    }

    /// A Reply chosen in edit mode ends the edit and keeps the new reply, so
    /// Return never sends an edit with a reply bar on screen.
    private func leaveEditForReply() {
        guard replyTo != nil, let session = editSession else { return }
        editSession = nil
        merged?.editDidEnd()
        chatInput = session.previousDraftText
    }

    /// Return in edit mode: sends the edit through the SDK, then ends edit
    /// mode. On a failure the composer stays in edit mode, so nothing is lost.
    private func saveEdit(_ session: ComposerEditSession) async {
        let decision = ComposerEdit.saveDecision(
            kind: session.target.kind,
            originalDraftText: session.target.originalDraftText,
            draftText: chatInput
        )
        switch decision {
        case .keepEditing:
            return
        case .finishWithoutSending:
            endEdit()
        case let .send(content):
            // A merged chat's edit goes to the room of the message.
            let owner = merged?.editTimeline ?? timeline
            do {
                try await owner.edit(session.target, with: content)
            } catch {
                Logger.viewCycle.error("failed to edit message: \(error)")
                return
            }
            // The user can start another edit while the call runs.
            guard editSession?.target == session.target else { return }
            endEdit()
        }
    }

    /// Restores an edit from a saved draft. The draft text is already in the
    /// composer, and there is no earlier draft to restore after the edit.
    func restoreEdit(eventId: String, in innerTimeline: MatrixRustSDK.Timeline) async {
        do {
            let item = try await innerTimeline.getEventTimelineItemByEventId(eventId: eventId)
            guard let target = MessageEditTarget(event: item) else {
                Logger.viewCycle.error("saved edit target is not editable: \(eventId)")
                return
            }
            editSession = ComposerEditSession(target: target, previousDraftText: "", previousReplyTo: nil)
        } catch {
            Logger.viewCycle.error("failed to resolve edit target: \(error)")
        }
    }
}

/* #Preview {
     ChatInputView()
 } */

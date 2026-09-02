import MatrixRustSDK
import OSLog
import SwiftUI
import Tokens

struct ChatInputView: View {
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency

    let room: Room
    let timeline: LiveTimeline
    @Binding var replyTo: MatrixRustSDK.EventTimelineItem?
    @AppStorage(TypographyToken.fontSizeStorageKey) var fontSize = TypographyToken.defaultBaseFontSize

    @State private var isDraftLoaded: Bool = false
    @State private var chatInput: String = ""

    func sendMessage() async {
        guard !chatInput.isEmpty else { return }
        guard let innerTimeline = timeline.timeline else { return }

        let msg = messageEventContentFromMarkdown(md: chatInput)

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
        timeline.requestScrollToBottom()
    }

    private func saveDraft() async {
        guard isDraftLoaded else { return } // avoid saving a draft hasn't yet been restored
        if chatInput.isEmpty, replyTo == nil {
            Logger.viewCycle.debug("clearing draft")
            do {
                try await room.clearComposerDraft(threadRoot: timeline.focusedThreadId)
            } catch {
                Logger.viewCycle.error("failed to clear draft: \(error)")
            }
            return
        }

        let draftType: ComposerDraftType = if let replyTo {
            .reply(eventId: replyTo.eventOrTransactionId.id)
        } else {
            .newMessage
        }
        let draft = ComposerDraft(
            plainText: chatInput,
            htmlText: nil,
            draftType: draftType,
            attachments: []
        )
        do {
            try await room.saveComposerDraft(draft: draft, threadRoot: timeline.focusedThreadId)
        } catch {
            Logger.viewCycle.error("failed save draft: \(error)")
        }
    }

    private func loadDraft() async {
        guard !isDraftLoaded else { return } // don't load a draft more than once
        do {
            guard let draft = try await room.loadComposerDraft(threadRoot: timeline.focusedThreadId) else {
                // no draft to load
                isDraftLoaded = true
                return
            }
            chatInput = draft.plainText
            switch draft.draftType {
            case .reply(eventId: let eventId):
                // we need a timeline to be able to populate the reply; return false so we can try again
                guard let innerTimeline = timeline.timeline else {
                    isDraftLoaded = false
                    return
                }

                do {
                    let item = try await innerTimeline.getEventTimelineItemByEventId(eventId: eventId)
                    timeline.sendReplyTo = item
                } catch {
                    Logger.viewCycle.error("failed to resolve reply target: \(error)")
                }
            case .newMessage, .edit:
                // nothing to do
                isDraftLoaded = true
                return
            }
        } catch {
            Logger.viewCycle.error("failed to load draft: \(error)")
        }
        isDraftLoaded = true // so we don't try again
    }

    private func chatInputChanged() async {
        guard isDraftLoaded else { return } // avoid working on a draft that's being restored
        if !chatInput.isEmpty {
            do {
                try await room.typingNotice(isTyping: !chatInput.isEmpty)
            } catch {
                Logger.viewCycle.warning("Failed to send typing notice: \(error)")
            }
        }
        await saveDraft()
    }

    var replyEmbeddedDetails: EmbeddedEventDetails? {
        guard let replyTo else { return nil }

        return .ready(content: replyTo.content, sender: replyTo.sender, senderProfile: replyTo.senderProfile, timestamp: replyTo.timestamp, eventOrTransactionId: replyTo.eventOrTransactionId)
    }

    var content: some View {
        VStack(alignment: .leading) {
            if let replyEmbeddedDetails {
                EmbeddedMessageView(embeddedEvent: replyEmbeddedDetails) {
                    replyTo = nil
                }
            }
            ChatTextView(
                text: $chatInput,
                placeholder: "Message \(room.displayName() ?? "room")",
                disabled: !isDraftLoaded,
                onSubmit: { Task { await sendMessage() } }
            )
        }
        .font(.system(size: .init(fontSize)))
        .task(id: chatInput) {
            await chatInputChanged()
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

/* #Preview {
     ChatInputView()
 } */

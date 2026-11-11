import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI

// MARK: - Draft

/// The room's composer draft, saved and loaded through the SDK. An edit in
/// progress is saved as an `.edit` draft (MATRIX-109).
///
/// A merged chat's composer (MATRIX-143) keeps its draft in memory instead
/// (`MergedComposerSession.saveDraft`, `MergedComposerDrafts`): its target
/// room can change while the user writes, so an SDK draft could land in a
/// room the message does not go to.
extension ChatInputView {
    func saveDraft() async {
        guard isDraftLoaded else { return } // avoid saving a draft hasn't yet been restored
        if let merged {
            merged.saveDraft(composerText: chatInput, textBeforeEdit: editSession?.previousDraftText)
            return
        }
        if chatInput.isEmpty, replyTo == nil, editSession == nil {
            Logger.viewCycle.debug("clearing draft")
            do {
                try await room.clearComposerDraft(threadRoot: timeline.focusedThreadId)
            } catch {
                Logger.viewCycle.error("failed to clear draft: \(error)")
            }
            return
        }

        let draftType: ComposerDraftType
        if let editSession {
            // A local echo has no event ID yet, so its edit is not saved.
            guard case let .eventId(eventId) = editSession.target.itemId else { return }
            draftType = .edit(eventId: eventId)
        } else if let replyTo {
            draftType = .reply(eventId: replyTo.eventOrTransactionId.id)
        } else {
            draftType = .newMessage
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

    func loadDraft() async {
        guard !isDraftLoaded else { return } // don't load a draft more than once
        if let merged {
            chatInput = merged.draftText
            isDraftLoaded = true
            return
        }
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
            case .edit(eventId: let eventId):
                // the edit target needs a timeline too; try again when it loads
                guard let innerTimeline = timeline.timeline else {
                    isDraftLoaded = false
                    return
                }
                await restoreEdit(eventId: eventId, in: innerTimeline)
            case .newMessage:
                // nothing to do
                isDraftLoaded = true
                return
            }
        } catch {
            Logger.viewCycle.error("failed to load draft: \(error)")
        }
        isDraftLoaded = true // so we don't try again
    }
}

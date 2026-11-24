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
            // MATRIX-224: the merged chat's row shows the draft.
            appState.matrixClient?.composerDrafts.mergedDraftDidChange(mergeId: merged.merge.id, text: merged.draftText)
            return
        }
        if chatInput.isEmpty, replyTo == nil, editSession == nil {
            Logger.viewCycle.debug("clearing draft")
            do {
                try await room.clearComposerDraft(threadRoot: timeline.focusedThreadId)
                reportDraftToChatList(nil)
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
            reportDraftToChatList(draft)
        } catch {
            Logger.viewCycle.error("failed save draft: \(error)")
        }
    }

    /// MATRIX-224: tells the chat list's draft cache what the store now
    /// holds, so the list does not read the store again. Only the main
    /// timeline's draft shows on the row.
    ///
    /// - Parameter draft: the saved draft, or nil after a clear.
    private func reportDraftToChatList(_ draft: ComposerDraft?) {
        guard timeline.focusedThreadId == nil else { return }
        appState.matrixClient?.composerDrafts.roomDraftDidChange(roomId: room.id(), draft: draft)
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

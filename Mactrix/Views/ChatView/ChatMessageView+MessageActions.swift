import AppKit
import Core
import MatrixRustSDK
import Models
import OSLog
import UI

// MARK: - Message actions (MATRIX-108)

/// The row side of the shared message-action model. The hover row, the
/// right-click menus (row and media), and the Edit menu all end in
/// `perform(_:)`, so each SDK call has one call site.
extension ChatMessageView {
    /// The input of the shared action model for this message.
    var messageActionSubject: MessageActionSubject {
        MessageActionSubject(
            event: event,
            msg: msg,
            pinnedEventIds: timeline?.room.roomInfo?.pinnedEventIds ?? [],
            redactPermission: timeline?.room.redactPermission ?? .none
        )
    }

    var actionSubject: MessageActionSubject? {
        messageActionSubject
    }

    /// This message as the Edit menu's target, and as the row actions a media
    /// view forwards to.
    var actionTarget: MessageActionTarget {
        MessageActionTarget(
            key: event.eventOrTransactionId.id,
            subject: messageActionSubject,
            quickReactionKeys: quickReactionKeys,
            hasMessageSelection: hasMessageSelection,
            perform: perform
        )
    }

    /// Runs one message action.
    ///
    /// B2 (edit), B3 (redact), B5 (forward), and B6 (copy messages) are in.
    func perform(_ action: MessageAction) {
        switch action {
        case .reply:
            reply()
        case .replyInThread:
            replyInThread()
        case let .toggleReaction(key):
            toggleReaction(key: key)
        case .openReactionPicker:
            openReactionPicker()
        case .edit:
            // The composer starts edit mode; it makes the SDK call on save.
            timeline?.requestEdit(of: event)
        case .forward:
            // The room view opens the room picker, then the confirmation;
            // `MatrixClient.forward(_:to:)` makes the SDK calls (MATRIX-112).
            timeline?.requestForward(of: event)
        case .copyText:
            copyText()
        case .copyLink:
            copyLink()
        case .pin:
            pin()
        case .unpin:
            unpin()
        case .redact:
            requestRedaction()
        case .copyMessages:
            timeline?.messageActionTarget.copySelection()
        case .quickLook, .playInline, .saveToDownloads:
            // The media view performs these; its menu never forwards them.
            Logger.viewCycle.error("media action reached the row: \(String(describing: action))")
        }
    }

    /// Unpins the message. The SDK returns false when the event was not
    /// pinned; that is a no-op, not an error.
    func unpin() {
        guard case let .eventId(eventId: eventId) = event.eventOrTransactionId else { return }
        Task {
            do {
                let wasSent = try await timeline?.timeline?.unpinEvent(eventId: eventId) ?? false
                Logger.viewCycle.debug("unpin \(eventId) sent: \(wasSent)")
            } catch {
                Logger.viewCycle.error("Failed to unpin message: \(error)")
            }
        }
    }

    /// Opens the delete confirmation for this message (MATRIX-110). The room
    /// view shows the sheet; `LiveTimeline.confirmRedaction` sends it.
    func requestRedaction() {
        timeline?.requestRedaction(of: event.eventOrTransactionId, isOwn: event.isOwn)
    }

    /// Puts the message's plain body, or its media caption, on the pasteboard.
    func copyText() {
        guard let text = messageActionSubject.copyableText, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Puts the message's matrix.to permalink on the pasteboard.
    func copyLink() {
        guard case let .eventId(eventId: eventId) = event.eventOrTransactionId,
              let room = timeline?.room.room
        else { return }
        Task {
            do {
                let permalink = try await room.matrixToEventPermalink(eventId: eventId)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(permalink, forType: .string)
                Logger.viewCycle.debug("copy message link: \(permalink)")
            } catch {
                Logger.viewCycle.error("unable to copy message link: \(error)")
            }
        }
    }

    /// Makes this message the Edit menu's target.
    func offerAsTarget() {
        timeline?.messageActionTarget.offer(actionTarget)
    }
}

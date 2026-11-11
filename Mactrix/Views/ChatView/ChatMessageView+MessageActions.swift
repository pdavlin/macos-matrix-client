import AppKit
import Core
import MatrixRustSDK
import Models
import OSLog
import UI

// MARK: - Message actions (MATRIX-108, MATRIX-145)

/// The actions of one message, apart from its row view.
///
/// The hover bar, the right-click menus (row and media), and the Edit menu
/// all end in `perform(_:)`, so each SDK call has one call site.
///
/// The row view builds this value from its inputs and its environment
/// (`ChatMessageView.rowActions`). The timeline controller builds the same
/// value for the row its floating hover bar shows for (MATRIX-145): a view's
/// environment cannot be read outside the view's body, so the actions live
/// in a value of their own, and the bar acts on exactly the hovered row.
@MainActor
struct ChatMessageActions {
    let timeline: LiveTimeline?
    let event: MatrixRustSDK.EventTimelineItem
    let msg: MatrixRustSDK.MsgLikeContent
    let appState: AppState
    let windowState: WindowState

    /// The input of the shared action model for this message.
    var messageActionSubject: MessageActionSubject {
        MessageActionSubject(
            event: event,
            msg: msg,
            pinnedEventIds: timeline?.room.roomInfo?.pinnedEventIds ?? [],
            redactPermission: timeline?.room.redactPermission ?? .none
        )
    }

    /// The hover bar's and the menus' quick reactions: the top three recent
    /// emoji, or the three defaults before the list loads (MATRIX-111).
    var quickReactionKeys: [String] {
        appState.matrixClient?.recentEmojis.quickReactionKeys ?? MessageActionModel.defaultQuickReactionKeys
    }

    /// Whether the timeline has a message selection (MATRIX-113).
    var hasMessageSelection: Bool {
        timeline?.messageActionTarget.hasMessageSelection ?? false
    }

    /// This message as the Edit menu's target, as the hover bar's target, and
    /// as the row actions a media view forwards to.
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

    /// Toggles the own reaction `key` on this message. Every reaction that
    /// is added, from the hover bar, a menu, the picker, or a reaction pill,
    /// counts as a use of the emoji in the account's recent list (D-3).
    /// `LiveTimeline.toggleReaction(key:on:recordingUseIn:)` holds that rule,
    /// shared with the timeline controller's picker popover (MATRIX-138).
    func toggleReaction(key: String) {
        let itemId = event.eventOrTransactionId
        let client = appState.matrixClient
        let timeline = timeline
        Task {
            await timeline?.toggleReaction(key: key, on: itemId, recordingUseIn: client)
        }
    }

    /// Opens the reaction picker on this message (MATRIX-111). The timeline
    /// controller shows it as an AppKit popover (MATRIX-138): a SwiftUI
    /// popover on a row in the timeline table did not open. The request
    /// carries the hover bar's layout, so the popover points at the picker
    /// button. The recent-emoji read runs here too, in case no room view
    /// started it yet; it is a no-op once the list has loaded.
    func openReactionPicker() {
        let hoverItems = MessageActionModel.items(
            for: messageActionSubject,
            on: .hoverRow,
            quickReactionKeys: quickReactionKeys
        )
        timeline?.requestReactionPicker(
            for: event.eventOrTransactionId,
            hoverButtonsAfterPicker: UI.HoverActionBarGeometry.buttonsAfter(.openReactionPicker, in: hoverItems)
        )
        let client = appState.matrixClient
        Task {
            await client?.loadRecentEmojisIfNeeded()
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
        let timeline = timeline
        Task {
            do {
                _ = try await timeline?.timeline?.pinEvent(eventId: eventId)
            } catch {
                Logger.viewCycle.error("Failed to ping message: \(error)")
            }
        }
    }

    /// Unpins the message. The SDK returns false when the event was not
    /// pinned; that is a no-op, not an error.
    func unpin() {
        guard case let .eventId(eventId: eventId) = event.eventOrTransactionId else { return }
        let timeline = timeline
        Task {
            do {
                let wasSent = try await timeline?.timeline?.unpinEvent(eventId: eventId) ?? false
                Logger.viewCycle.debug("unpin \(eventId) sent: \(wasSent)")
            } catch {
                Logger.viewCycle.error("Failed to unpin message: \(error)")
            }
        }
    }

    func focusUser() {
        Logger.viewCycle.info("Focusing user \(event.sender)")
        windowState.focusUser(userId: event.sender)
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

/// The row side of the shared message-action model. The row forwards to
/// `rowActions`, so the row and the timeline's hover bar run the same code.
extension ChatMessageView {
    /// The input of the shared action model for this message.
    var messageActionSubject: MessageActionSubject {
        rowActions.messageActionSubject
    }

    var actionSubject: MessageActionSubject? {
        messageActionSubject
    }

    /// This message as the Edit menu's target, and as the row actions a media
    /// view forwards to.
    var actionTarget: MessageActionTarget {
        rowActions.actionTarget
    }

    /// Runs one message action.
    func perform(_ action: MessageAction) {
        rowActions.perform(action)
    }

    /// Makes this message the Edit menu's target.
    func offerAsTarget() {
        rowActions.offerAsTarget()
    }
}

import Core
import MatrixRustSDK
import Models
import SwiftUI
import UI

// MARK: - Send Later (MATRIX-212)

/// The sheet the composer shows for Send Later.
enum SendLaterSheetRequest: Identifiable {
    /// Schedule the composer's message.
    case schedule(text: ScheduledMessageText, draftText: String, roomId: String, chatName: String)
    /// Edit a scheduled message.
    case edit(ScheduledMessageItem, chatName: String)

    var id: String {
        switch self {
        case let .schedule(_, _, roomId, _): "schedule-\(roomId)"
        case let .edit(item, _): "edit-\(item.id)"
        }
    }
}

/// A failed Send Later action, for the alert.
struct SendLaterAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension ChatInputView {
    var scheduledMessages: ScheduledMessagesModel? {
        appState.matrixClient?.scheduledMessages
    }

    /// The main composer of a room or a merged chat has Send Later. The
    /// thread panel's composer does not: the content has no thread
    /// relation, so the message would show in the main timeline.
    var hasSendLater: Bool {
        timeline.focusedThreadId == nil
    }

    /// Send Later is on: text, and no reply, edit, or attachment. The
    /// content has no relation and no attachment (plain text only, contract
    /// §11 2026-11-23).
    var canSendLater: Bool {
        guard hasSendLater, isDraftLoaded, editSession == nil, replyTo == nil, attachments.isEmpty,
              let model = scheduledMessages, model.isEditable
        else { return false }
        // A chip is text in the draft, so this matches the body's check
        // without the markdown read on each key.
        return !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The chat's name for the sheet titles: the merged chat's name, or
    /// the room's.
    private var chatName: String {
        merged?.merge.name ?? room.displayName() ?? "this chat"
    }

    /// The rooms whose scheduled messages the strip shows: every member of
    /// a merged chat, or the room.
    private var scheduledRoomIds: Set<String> {
        if let merged {
            return Set(merged.members.map(\.room.id))
        }
        return [timeline.room.id]
    }

    /// Opens the Send Later sheet for the composer's message: the menu item
    /// and Option-Command-Return.
    ///
    /// - Returns: false when Send Later is off.
    @discardableResult
    func openSendLater() -> Bool {
        guard canSendLater else { return false }
        // MATRIX-156: a `:name:` of the room's image packs would send as an
        // image. As plain text it stays text, so it counts as formatting.
        let packs = appState.matrixClient?.imagePacks.packs(forRoom: timeline.room.id) ?? []
        let outgoing = MentionMarkdown.outgoingMessage(fromDraftText: chatInput)
        let text = ScheduledMessageText(
            draftText: chatInput,
            hasCustomEmoji: outgoing.resolvingEmoji(in: packs).markdown != outgoing.markdown
        )
        sendLaterSheet = .schedule(text: text, draftText: chatInput, roomId: timeline.room.id, chatName: chatName)
        return true
    }

    // MARK: Strip

    /// The "2 scheduled" strip above the composer.
    @ViewBuilder
    var scheduledStrip: some View {
        if hasSendLater, let model = scheduledMessages {
            let items = model.items(inRooms: scheduledRoomIds)
            if !items.isEmpty {
                // The relative times in the list move on each minute.
                TimelineView(.everyMinute) { context in
                    UI.ScheduledMessagesStrip(
                        items: items,
                        busyIds: model.busyDelayIds,
                        isEditable: model.isEditable,
                        now: context.date,
                        actions: ScheduledMessageActions(
                            sendNow: { item in sendScheduledNow(item) },
                            edit: { item in sendLaterSheet = .edit(item, chatName: chatName) },
                            cancel: { item in cancelScheduled(item) }
                        )
                    )
                }
            }
        }
    }

    // MARK: Sheets and alerts

    /// The composer chrome with the Scheduled strip above it, the
    /// composer's padding, the Send Later and Edit sheets, and the failure
    /// alert.
    func withSendLater(_ chrome: some View) -> some View {
        VStack(spacing: 8) {
            scheduledStrip
            chrome
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
        .sheet(item: $sendLaterSheet) { request in
            sendLaterSheetContent(request)
        }
        .alert(
            sendLaterAlert?.title ?? "",
            isPresented: Binding(
                get: { sendLaterAlert != nil },
                set: { if !$0 { sendLaterAlert = nil } }
            ),
            presenting: sendLaterAlert
        ) { _ in
            Button("OK") { sendLaterAlert = nil }
        } message: { alert in
            Text(alert.message)
        }
    }

    /// The Send Later and Edit sheets.
    @ViewBuilder
    private func sendLaterSheetContent(_ request: SendLaterSheetRequest) -> some View {
        switch request {
        case let .schedule(text, draftText, roomId, chatName):
            UI.SendLaterSheet(chatName: chatName, text: text) { date in
                schedule(text, draftText: draftText, roomId: roomId, at: date)
            }
        case let .edit(item, chatName):
            UI.SendLaterEditSheet(chatName: chatName, text: item.text ?? "", sendAt: item.message.sendAt) { text, date in
                saveScheduledEdit(item, text: text, at: date)
            }
        }
    }

    // MARK: Actions

    /// Schedules the message. A success clears the composer, unless the
    /// user changed the text in the meantime. A failure keeps the text.
    private func schedule(_ text: ScheduledMessageText, draftText: String, roomId: String, at date: Date) {
        guard let model = scheduledMessages else { return }
        Task {
            do throws(ScheduledMessageFailure) {
                try await model.schedule(text: text.body, roomId: roomId, sendAt: date)
            } catch {
                sendLaterAlert = SendLaterAlert(title: "Could Not Schedule Message", message: error.message)
                return
            }
            if chatInput == draftText {
                chatInput = ""
            }
        }
    }

    private func sendScheduledNow(_ item: ScheduledMessageItem) {
        guard let model = scheduledMessages else { return }
        Task {
            do throws(ScheduledMessageFailure) {
                try await model.sendNow(delayId: item.id)
            } catch {
                sendLaterAlert = SendLaterAlert(title: "Could Not Send Message", message: error.message)
            }
        }
    }

    private func cancelScheduled(_ item: ScheduledMessageItem) {
        guard let model = scheduledMessages else { return }
        Task {
            do throws(ScheduledMessageFailure) {
                try await model.cancel(delayId: item.id)
            } catch {
                sendLaterAlert = SendLaterAlert(title: "Could Not Cancel Message", message: error.message)
            }
        }
    }

    /// Edit: a cancel, then a new schedule. When the new schedule fails
    /// after the cancel, the text goes back into the composer, so it is
    /// not lost.
    private func saveScheduledEdit(_ item: ScheduledMessageItem, text: String, at date: Date) {
        guard let model = scheduledMessages else { return }
        Task {
            do throws(ScheduledMessageEditFailure) {
                try await model.edit(delayId: item.id, text: text, sendAt: date)
            } catch {
                switch error {
                case let .notCancelled(failure):
                    sendLaterAlert = SendLaterAlert(title: "Could Not Edit Message", message: failure.message)
                case let .notRescheduled(failure, text):
                    chatInput = chatInput.isEmpty ? text : chatInput + "\n\n" + text
                    sendLaterAlert = SendLaterAlert(
                        title: "Could Not Edit Message",
                        message: "The old message was cancelled, but the new one was not scheduled. "
                            + "\(failure.message) The text is back in the composer."
                    )
                }
            }
        }
    }
}

import Foundation
import Models
import OSLog

/// The live layer of the notification actions (MATRIX-221). Each action
/// uses the SDK client and the account's models, not a view or a window,
/// so it works while Mactrix is in the background.
///
/// - Reply: `MatrixClient.sendText(_:toRoom:threadRoot:)`, the broadcast's
///   text path: the composer's `messageEventContentFromMarkdown(md:)` and
///   `Timeline.send(msg:)` on a send-only timeline. A reply in a thread
///   goes out through a timeline with the focus on that thread.
/// - Mark as Read: `MatrixClient.markAsRead(roomIds:)`, the chat list's Mark
///   as Read: `Room.markAsRead(receiptType: .read)` on the latest event, and
///   the marked-unread flag cleared.
/// - Remind in 1 Hour: `InboxStateModel.remind(roomIds:at:)` (MATRIX-207).
@MainActor
final class LiveNotificationActions: NotificationActionPerformer {
    private weak var client: MatrixClient?

    init(client: MatrixClient) {
        self.client = client
    }

    /// The reply reaches the send queue, or a notification says that it
    /// did not. A failure after that shows on the local echo in the chat.
    func sendReply(_ text: String, toRoom roomId: String, threadRoot: String?) async {
        guard let client else { return }
        do {
            try await client.sendText(text, toRoom: roomId, threadRoot: threadRoot)
            Logger.notification.info("notification reply queued for \(roomId) in thread \(threadRoot ?? "<none>")")
        } catch {
            Logger.notification.error("notification reply to \(roomId) not sent: \(String(describing: error), privacy: .public)")
            await client.notifications.postLocalNotification(title: "Reply not sent", body: text, roomId: roomId)
        }
    }

    func markAsRead(roomIds: [String]) async {
        // After a sign-out the SDK client is gone.
        guard let client, client.client != nil else { return }
        await client.markAsRead(roomIds: roomIds)
    }

    func remind(roomIds: [String], at date: Date) async {
        guard let inbox = client?.inbox, inbox.isEditable else {
            Logger.notification.error("no reminder for \(roomIds): the inbox states cannot be written")
            return
        }
        await inbox.remind(roomIds: roomIds, at: date).value
    }

    func removeDeliveredNotifications(roomIds: [String]) async {
        await client?.notifications.removeDeliveredMessageNotifications(roomIds: roomIds)
    }
}

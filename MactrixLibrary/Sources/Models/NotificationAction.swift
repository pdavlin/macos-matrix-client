import Foundation

/// What the user did with a message notification (MATRIX-221).
///
/// A message notification has the category `messageCategoryIdentifier`,
/// with three actions: Reply (a text input), Mark as Read, and Remind in
/// 1 Hour. No action opens Mactrix: each one runs in the background. A
/// click on the notification opens the chat.
public enum NotificationAction: Equatable, Sendable {
    /// A click on the notification: open its chat.
    case open
    /// Reply: send the text to the notification's room.
    case reply(String)
    /// Mark as Read: a read receipt on the chat's latest event.
    case markAsRead
    /// Remind in 1 Hour: a MATRIX-207 reminder on the chat.
    case remindInOneHour

    /// The category of a message notification.
    public static let messageCategoryIdentifier = "matrix.message"
    /// The identifier of the Reply action.
    public static let replyIdentifier = "matrix.reply"
    /// The identifier of the Mark as Read action.
    public static let markAsReadIdentifier = "matrix.markAsRead"
    /// The identifier of the Remind in 1 Hour action.
    public static let remindInOneHourIdentifier = "matrix.remindInOneHour"

    /// The action of a notification response.
    ///
    /// - Parameters:
    ///   - identifier: the response's action identifier.
    ///   - defaultIdentifier: the system's identifier of a click on the
    ///     notification (`UNNotificationDefaultActionIdentifier`).
    ///   - userText: the text of a text input response, or nil.
    /// - Returns: nil for a dismiss, an unknown identifier, and a reply with
    ///   no text other than spaces and line breaks.
    public init?(identifier: String, defaultIdentifier: String, userText: String?) {
        switch identifier {
        case defaultIdentifier:
            self = .open
        case Self.replyIdentifier:
            guard let userText, !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            self = .reply(userText)
        case Self.markAsReadIdentifier:
            self = .markAsRead
        case Self.remindInOneHourIdentifier:
            self = .remindInOneHour
        default:
            return nil
        }
    }
}

/// The message that a notification is about (MATRIX-221): its room, its
/// event, and the root of the event's thread. A notification keeps them
/// in its `userInfo`.
public struct NotificationTarget: Equatable, Sendable {
    /// The `userInfo` key of the room ID. The local notifications and the
    /// MATRIX-89 Notification Service Extension both set it.
    public static let roomIdKey = "roomId"
    /// The `userInfo` key of the event ID.
    public static let eventIdKey = "eventId"
    /// The `userInfo` key of the thread root's event ID.
    public static let threadRootKey = "threadRoot"
    /// The `userInfo` key that marks a snooze end or a reminder (MATRIX-207).
    public static let reminderKey = "reminder"

    public var roomId: String
    /// The notified event, or nil for an invite.
    public var eventId: String?
    /// The root of the notified event's thread, or nil when the event is
    /// not in a thread.
    public var threadRoot: String?

    public init(roomId: String, eventId: String? = nil, threadRoot: String? = nil) {
        self.roomId = roomId
        self.eventId = eventId
        self.threadRoot = threadRoot
    }

    /// The target in a notification's `userInfo`, or nil when it has no
    /// room ID.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let roomId = userInfo[Self.roomIdKey] as? String else { return nil }
        self.init(
            roomId: roomId,
            eventId: userInfo[Self.eventIdKey] as? String,
            threadRoot: userInfo[Self.threadRootKey] as? String
        )
    }

    /// The `userInfo` of a notification for this target.
    public var userInfo: [String: String] {
        var info = [Self.roomIdKey: roomId]
        info[Self.eventIdKey] = eventId
        info[Self.threadRootKey] = threadRoot
        return info
    }

    /// The delivered message notifications of `roomIds`, to remove when
    /// their chat is read. A snooze end or a reminder stays: it is not a
    /// message.
    ///
    /// - Parameters:
    ///   - delivered: the identifier and `userInfo` of each delivered
    ///     notification.
    ///   - roomIds: the rooms of the chat.
    /// - Returns: the identifiers to remove, in the order of `delivered`.
    public static func messageNotificationIdentifiers(
        in delivered: [(identifier: String, userInfo: [AnyHashable: Any])],
        roomIds: Set<String>
    ) -> [String] {
        delivered.compactMap { notification in
            guard let target = NotificationTarget(userInfo: notification.userInfo),
                  roomIds.contains(target.roomId),
                  notification.userInfo[reminderKey] as? Bool != true
            else { return nil }
            return notification.identifier
        }
    }
}

/// The SDK and notification-center calls of the notification actions
/// (MATRIX-221). `Core` has the live layer; the tests use a fake.
@MainActor
public protocol NotificationActionPerformer: AnyObject {
    /// Puts `text` into the send queue of `roomId` as a message that quotes
    /// nothing: into the thread of `threadRoot`, or into the main timeline
    /// when it is nil.
    func sendReply(_ text: String, toRoom roomId: String, threadRoot: String?) async
    /// Sends a read receipt on the latest event of each room.
    func markAsRead(roomIds: [String]) async
    /// Sets a MATRIX-207 reminder on the rooms for `date`.
    func remind(roomIds: [String], at date: Date) async
    /// Removes the delivered message notifications of the rooms.
    func removeDeliveredNotifications(roomIds: [String]) async
}

/// Runs a notification action (MATRIX-221).
///
/// - Reply goes to the notification's own room, also when the room is in a
///   merged chat. A message in a thread gets its reply in that thread. The
///   reply quotes nothing.
/// - Mark as Read and Remind in 1 Hour act on the chat: the room, or every
///   member of the merged chat that holds the room (MATRIX-139), as the
///   chat list's Mark as Read and Remind me later do.
@MainActor
public enum NotificationActionRouter {
    /// Runs `action` for the notification of `target`. `.open` does
    /// nothing here: the notification delegate selects the chat.
    ///
    /// - Parameters:
    ///   - action: the action.
    ///   - target: the notification's message.
    ///   - merges: the account's merged chats.
    ///   - now: the current time, the start of Remind in 1 Hour.
    ///   - performer: the SDK layer.
    public static func perform(
        _ action: NotificationAction,
        on target: NotificationTarget,
        merges: MergedChatDocument,
        now: Date,
        performer: some NotificationActionPerformer
    ) async {
        switch action {
        case .open:
            return
        case let .reply(text):
            await performer.sendReply(text, toRoom: target.roomId, threadRoot: target.threadRoot)
        case .markAsRead:
            let roomIds = InboxStateDocument.chatRoomIds(for: [target.roomId], merges: merges)
            await performer.removeDeliveredNotifications(roomIds: roomIds)
            await performer.markAsRead(roomIds: roomIds)
        case .remindInOneHour:
            guard let date = InboxTimeChoice.oneHour.date(now: now) else { return }
            let roomIds = InboxStateDocument.chatRoomIds(for: [target.roomId], merges: merges)
            await performer.remind(roomIds: roomIds, at: date)
        }
    }
}

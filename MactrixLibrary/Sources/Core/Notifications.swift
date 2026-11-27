#if os(macOS)
    import AppKit
#endif
import MatrixRustSDK
import Models
import OSLog
import UserNotifications

// This class is Sendable because MatrixRustSDK.SyncNotificationListener requires it to be so
@MainActor @Observable public final class MatrixNotifications: NSObject {
    /// The `userInfo` key of the room id. The local notifications and the
    /// MATRIX-89 Notification Service Extension both set it.
    public nonisolated static let roomIDUserInfoKey = NotificationTarget.roomIdKey

    /// The `userInfo` key that marks a snooze end or a reminder
    /// (MATRIX-207). It shows even for the chat on screen (MATRIX-215).
    public nonisolated static let reminderUserInfoKey = NotificationTarget.reminderKey

    public var selectedRoomId: String?

    /// MATRIX-215: the key window's state, or nil when no Mactrix window is
    /// key. The app sets it when the key window changes. While Mactrix is
    /// active, a message for the chat that this window shows does not show
    /// as a notification (`NotificationPresentation`).
    @ObservationIgnored public weak var keyWindow: WindowState?

    /// MATRIX-77: rooms whose every label is muted. Mactrix shows no
    /// notification for them; push rules and other clients are untouched.
    @ObservationIgnored var labelMutedRoomIds: Set<String> = []

    /// MATRIX-117: the store that holds Settings > Notifications. Read for
    /// each notification, so a change in Settings applies at once.
    @ObservationIgnored private let settingsStore: UserDefaults

    /// MATRIX-144: the account's merged chats, read for each notification. A
    /// message from a member room then shows with the merged chat's name and
    /// stacks with its siblings (`MergedNotificationRemap`). Defaults to no
    /// merges, which shows every notification as before MATRIX-144; the M2.5
    /// integration story sets it to the merged-chats model's document.
    @ObservationIgnored public var mergedChats: @MainActor () -> MergedChatDocument = { MergedChatDocument() }

    /// MATRIX-221: the layer that runs Reply, Mark as Read, and Remind in 1
    /// Hour. `startSync()` sets it and `reset()` clears it. While it is nil,
    /// an action does nothing.
    @ObservationIgnored public var actionPerformer: (any NotificationActionPerformer)?

    public typealias NotificationEvent = (item: MatrixRustSDK.NotificationItem, roomId: String)

    @ObservationIgnored private let notificationContinuation: AsyncStream<NotificationEvent>.Continuation
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    /// - Parameter settingsStore: the defaults store that Settings >
    ///   Notifications writes with `@AppStorage`.
    public init(settingsStore: UserDefaults = .standard) {
        self.settingsStore = settingsStore
        let (stream, continuation) = AsyncStream<NotificationEvent>.makeStream()
        notificationContinuation = continuation

        super.init()
        UNUserNotificationCenter.current().delegate = self
        #if os(macOS)
            // MATRIX-221: the actions of a message notification. The iOS
            // app and its Notification Service Extension do not use them yet.
            UNUserNotificationCenter.current().setNotificationCategories([Self.messageCategory])
        #endif

        streamTask = Task { [weak self] in
            for await (notification, roomId) in stream {
                guard let self else { break }
                await self.sendNotification(notification: notification, roomId: roomId)
            }
        }
    }
}

extension MatrixNotifications: @MainActor UNUserNotificationCenterDelegate {
    /// A click opens the chat. Reply, Mark as Read, and Remind in 1 Hour
    /// (MATRIX-221) run in the background: they open no window, and they
    /// need no window that shows the chat. macOS waits until this method
    /// returns, so each action is done or queued by then.
    public func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let target = NotificationTarget(userInfo: response.notification.request.content.userInfo)
        let action = NotificationAction(
            identifier: response.actionIdentifier,
            defaultIdentifier: UNNotificationDefaultActionIdentifier,
            userText: (response as? UNTextInputNotificationResponse)?.userText
        )
        Logger.notification.info(
            "Notification delegate didReceive \(response.actionIdentifier, privacy: .public): \(target?.roomId ?? "<no room id>")"
        )
        guard let target, let action else { return }
        if action == .open {
            selectedRoomId = target.roomId
            return
        }
        guard let actionPerformer else {
            Logger.notification.error("notification action for \(target.roomId): the account is not ready")
            return
        }
        await NotificationActionRouter.perform(action, on: target, merges: mergedChats(), now: .now, performer: actionPerformer)
    }

    #if os(macOS)
        /// MATRIX-215: what macOS shows for a notification that arrives while
        /// Mactrix is active. Without this method macOS shows nothing.
        public func userNotificationCenter(
            _: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            let userInfo = notification.request.content.userInfo
            let shows = NotificationPresentation.shows(
                roomId: userInfo[Self.roomIDUserInfoKey] as? String,
                isReminder: userInfo[Self.reminderUserInfoKey] as? Bool ?? false,
                appIsActive: NSApp.isActive,
                keyWindowSelection: keyWindow?.chatSelection,
                document: mergedChats()
            )
            return shows ? [.banner, .list, .sound] : []
        }
    #endif
}

#if os(macOS)
    extension MatrixNotifications {
        /// MATRIX-221: the category of a message notification. No action
        /// has the `.foreground` option, so none of them brings Mactrix
        /// forward.
        static var messageCategory: UNNotificationCategory {
            UNNotificationCategory(
                identifier: NotificationAction.messageCategoryIdentifier,
                actions: [
                    UNTextInputNotificationAction(
                        identifier: NotificationAction.replyIdentifier,
                        title: "Reply",
                        options: [],
                        textInputButtonTitle: "Send",
                        textInputPlaceholder: "Message"
                    ),
                    UNNotificationAction(identifier: NotificationAction.markAsReadIdentifier, title: "Mark as Read", options: []),
                    UNNotificationAction(identifier: NotificationAction.remindInOneHourIdentifier, title: "Remind in 1 Hour", options: []),
                ],
                intentIdentifiers: [],
                options: []
            )
        }
    }
#endif

extension MatrixNotifications: MatrixRustSDK.SyncNotificationListener {
    public nonisolated func onNotification(notification: MatrixRustSDK.NotificationItem, roomId: String) {
        notificationContinuation.yield((notification, roomId))
    }
}

public extension MatrixNotifications {
    func sendNotification(notification: MatrixRustSDK.NotificationItem, roomId: String) async {
        let decision = NotificationDecision.decide(
            isMutedByLabel: labelMutedRoomIds.contains(roomId),
            settings: NotificationPreferences(defaults: settingsStore)
        )
        let playsSound: Bool
        switch decision {
        case .post(playsSound: let withSound):
            playsSound = withSound
        case .suppress(.mutedByLabel):
            Logger.notification.debug("skipping notification from room \(roomId): muted by label")
            return
        case .suppress(.notificationsOff):
            Logger.notification.debug("skipping notification from room \(roomId): notifications are off in Settings")
            return
        }

        // MATRIX-261: no banner for a reply in a thread that the account does
        // not follow, as the server's push rules decide for the phone. It
        // does nothing while the server's MSC4306 support is not known.
        if case let .timeline(event: event) = notification.event {
            let shows = await ThreadFollowStore.shared.bannerShows(
                roomId: roomId,
                threadRoot: event.threadRootEventId() ?? notification.threadId,
                hasMention: notification.hasMention
            )
            guard shows else {
                Logger.notification.debug("skipping notification from room \(roomId): thread not followed")
                return
            }
        }

        let content = UNMutableNotificationContent()
        let remap = mergedRemap(for: notification, roomId: roomId)
        content.title = remap?.title ?? notificationTitle(for: notification)
        if let threadIdentifier = remap?.threadIdentifier {
            content.threadIdentifier = threadIdentifier
        }
        content.subtitle = notificationBody(for: notification)
        content.sound = playsSound ? UNNotificationSound.default : nil
        if case let .timeline(event: event) = notification.event {
            content.userInfo = NotificationTarget(
                roomId: roomId,
                eventId: event.eventId(),
                threadRoot: event.threadRootEventId() ?? notification.threadId
            ).userInfo
            #if os(macOS)
                // MATRIX-221: Reply, Mark as Read, Remind in 1 Hour. An
                // invite gets none of them.
                content.categoryIdentifier = NotificationAction.messageCategoryIdentifier
            #endif
        } else {
            content.userInfo = NotificationTarget(roomId: roomId).userInfo
        }
        await post(content, roomId: roomId)
    }

    /// Posts a local notification that no Matrix event carries: a snooze
    /// end or a reminder (MATRIX-207). Settings > Notifications applies; a
    /// click opens `roomId`.
    func postLocalNotification(title: String, body: String, roomId: String) async {
        let decision = NotificationDecision.decide(isMutedByLabel: false, settings: NotificationPreferences(defaults: settingsStore))
        guard case let .post(playsSound) = decision else {
            Logger.notification.debug("skipping local notification for \(roomId): notifications are off in Settings")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = playsSound ? UNNotificationSound.default : nil
        content.userInfo = [Self.roomIDUserInfoKey: roomId, Self.reminderUserInfoKey: true]
        await post(content, roomId: roomId)
    }

    /// MATRIX-215: the one path to macOS for every notification, a message
    /// or a local one. The permission is asked once per launch
    /// (`NotificationPermissionModel`), not for each notification, and read
    /// before each one: while macOS blocks notifications, nothing posts and
    /// nothing logs above debug level.
    private func post(_ content: UNMutableNotificationContent, roomId: String) async {
        let permissions = NotificationPermissionModel.shared
        await permissions.requestAuthorizationOnce()
        guard await permissions.refresh() == .allowed else {
            Logger.notification.debug("skipping notification from room \(roomId): macOS does not allow notifications")
            return
        }

        Logger.notification.debug("sending notification from room \(roomId)")
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.01, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Logger.notification.error("failed to schedule notification: \(error)")
        }
    }

    /// MATRIX-221: removes the delivered message notifications of
    /// `roomIds`, for Mark as Read. A snooze end or a reminder stays.
    func removeDeliveredMessageNotifications(roomIds: [String]) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let identifiers = NotificationTarget.messageNotificationIdentifiers(
            in: delivered.map { ($0.request.identifier, $0.request.content.userInfo) },
            roomIds: Set(roomIds)
        )
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func notificationTitle(for notification: NotificationItem) -> String {
        switch notification.event {
        case let .invite(sender: sender):
            return "\(sender) invited you to a room"
        case let .timeline(event: event):
            let sender = notification.senderInfo.displayName ?? event.senderId()
            return MergedNotificationRemap.title(senderDisplayName: sender, chatName: notification.roomInfo.displayName)
        }
    }

    /// MATRIX-144: the merged-chat presentation of a message notification, or
    /// nil for an invite. An invite is never for a member room (members are
    /// joined rooms), so it keeps its own title.
    ///
    /// - Parameters:
    ///   - notification: the SDK notification.
    ///   - roomId: the room it comes from.
    /// - Returns: the title and thread identifier to use.
    func mergedRemap(for notification: NotificationItem, roomId: String) -> MergedNotificationRemap? {
        guard case let .timeline(event: event) = notification.event else { return nil }
        return MergedNotificationRemap.remap(
            roomId: roomId,
            roomDisplayName: notification.roomInfo.displayName,
            senderDisplayName: notification.senderInfo.displayName ?? event.senderId(),
            document: mergedChats()
        )
    }

    func notificationBody(for notification: NotificationItem) -> String {
        switch notification.event {
        case .invite:
            return "Room \(notification.roomInfo.displayName)"
        case let .timeline(event: event):
            do {
                switch try event.content() {
                case let .messageLike(content: msgLike):
                    switch msgLike {
                    case .callAnswer:
                        return "Call answered"
                    case .callInvite:
                        return "Call invitation"
                    case .rtcNotification:
                        return "RTC Notification"
                    case .callHangup:
                        return "Call hang up"
                    case .callCandidates:
                        return "Call candidates"
                    case .keyVerificationReady:
                        return "Key verification ready"
                    case .keyVerificationStart:
                        return "Key verification start"
                    case .keyVerificationCancel:
                        return "Key verification cancel"
                    case .keyVerificationAccept:
                        return "Key verification accept"
                    case .keyVerificationKey:
                        return "Key verification key"
                    case .keyVerificationMac:
                        return "Key verification mac"
                    case .keyVerificationDone:
                        return "Key verification done"
                    case let .poll(question):
                        return "Asked \(question)"
                    case .reactionContent:
                        return "Reaction content"
                    case .beacon:
                        // SDK 26.11.11 added this case (a live location update).
                        return "Live location"
                    case .roomEncrypted:
                        return "Room encrypted"
                    case let .roomMessage(messageType, _):
                        switch messageType {
                        case .emote:
                            return "Emote"
                        case .image:
                            return "Image"
                        case .audio:
                            return "Audio"
                        case .video:
                            return "Video"
                        case .file:
                            return "File"
                        case .gallery:
                            return "Gallery"
                        case .notice:
                            return "Notice"
                        case let .text(content):
                            return content.displayBody
                        case .location:
                            return "Location"
                        case let .other(msgtype, body):
                            return "\(msgtype): \(body)"
                        }
                    case .roomRedaction:
                        return "Message redacted"
                    case .sticker:
                        return "Sent a sticker"
                    }
                case .state(content:):
                    return "State change"
                }
            } catch {
                return error.localizedDescription
            }
        }
    }
}

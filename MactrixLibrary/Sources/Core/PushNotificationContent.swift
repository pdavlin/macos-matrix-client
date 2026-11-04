import Foundation
import MatrixRustSDK
import OSLog
import Utils

/// MATRIX-89: the Notification Service Extension's lookup of a pushed event.
public enum PushNotificationContent {
    /// Resolves the pushed event with the SDK and returns the banner text, or
    /// `nil` if the extension must keep the generic content of the push.
    ///
    /// `.eventFilteredOut` and `.eventRedacted` also return `nil`. To remove a
    /// notification, the extension needs the
    /// `com.apple.developer.usernotifications.filtering` entitlement, which
    /// this app does not have. So those pushes show the generic content.
    @MainActor
    public static func display(for payload: PushNotificationPayload) async -> NotificationDisplay? {
        do {
            let service = try await MatrixClient.notificationServiceClient()
            let status = try await service.notificationClient.getNotification(roomId: payload.roomID, eventId: payload.eventID)
            switch status {
            case let .event(item):
                return NotificationDisplay(summary: item.summary(roomID: payload.roomID))
            case .eventNotFound:
                Logger.notification.warning("push: event not found, showing the generic content")
            case .eventFilteredOut:
                Logger.notification.info("push: event filtered out by the push rules, showing the generic content")
            case .eventRedacted:
                Logger.notification.info("push: event redacted, showing the generic content")
            }
        } catch {
            Logger.notification.error("push: failed to resolve the event: \(String(describing: error), privacy: .public)")
        }
        return nil
    }
}

extension NotificationItem {
    /// The SDK-free summary that `NotificationDisplay` formats.
    func summary(roomID: String) -> NotificationSummary {
        let sender: String
        let body: NotificationSummary.Body
        switch event {
        case let .invite(sender: inviter):
            sender = senderInfo.displayName ?? inviter
            body = .invite
        case let .timeline(event: timelineEvent):
            sender = senderInfo.displayName ?? timelineEvent.senderId()
            body = Self.body(of: timelineEvent)
        }
        return NotificationSummary(
            roomID: roomID,
            roomDisplayName: roomInfo.displayName,
            isDirect: roomInfo.isDirect,
            senderDisplayName: sender,
            body: body,
            isNoisy: isNoisy
        )
    }

    private static func body(of event: TimelineEvent) -> NotificationSummary.Body {
        guard let content = try? event.content() else { return .other }
        switch content {
        case let .messageLike(content: messageLike):
            switch messageLike {
            case let .roomMessage(messageType: messageType, inReplyToEventId: _):
                return body(of: messageType)
            case .roomEncrypted:
                return .encrypted
            case .sticker:
                return .sticker
            case .poll:
                return .poll
            default:
                return .other
            }
        case .state:
            return .other
        }
    }

    private static func body(of messageType: MessageType) -> NotificationSummary.Body {
        switch messageType {
        case let .text(content: content):
            .text(content.body)
        case let .notice(content: content):
            .text(content.body)
        case let .emote(content: content):
            .text(content.body)
        case .image, .gallery:
            .image
        case .video:
            .video
        case .audio:
            .audio
        case .file:
            .file
        case .location:
            .location
        case let .other(msgtype: _, body: body):
            .text(body)
        }
    }
}

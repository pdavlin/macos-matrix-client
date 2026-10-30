import Core
import Foundation
import OSLog
import UserNotifications
import Utils

/// MATRIX-89: rewrites an APNs push with the decrypted sender and body.
///
/// Sygnal sends `event_id_only` pushes: a generic alert, `mutable-content`,
/// and the room and event identifiers. This extension resolves the event with
/// the SDK from the App Group store and replaces the generic text. Every path
/// delivers some content: the resolved text, or the generic text of the push.
/// No media downloads: the extension memory limit is about 24 MB.
final class NotificationService: UNNotificationServiceExtension {
    private let delivery = NotificationDelivery()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.davlin.matrixclient.ios.notifications",
        category: "notification-service"
    )

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let fallback = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        // A push arrives only for an event that the push rules say to notify.
        fallback.sound = .default

        guard let payload = PushNotificationPayload(userInfo: request.content.userInfo) else {
            Self.logger.error("push without a valid room_id and event_id: showing the generic content")
            delivery.start(contentHandler: contentHandler, fallback: fallback)
            delivery.finish(with: nil)
            return
        }

        fallback.threadIdentifier = payload.roomID
        // The key that `MatrixNotifications` reads when the user taps a notification.
        fallback.userInfo[MatrixNotifications.roomIDUserInfoKey] = payload.roomID
        delivery.start(contentHandler: contentHandler, fallback: fallback)

        let delivery = delivery
        delivery.setLookup(Task { @MainActor in
            let display = await PushNotificationContent.display(for: payload)
            delivery.finish(with: display)
        })
    }

    override func serviceExtensionTimeWillExpire() {
        Self.logger.warning("extension time expired: showing the best content so far")
        delivery.cancelLookup()
        delivery.finish(with: nil)
    }
}

/// Calls the content handler exactly once, from whichever path finishes first:
/// the lookup or `serviceExtensionTimeWillExpire`. The system can call the
/// extension on any thread, so a lock guards the state.
private final class NotificationDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?
    private var lookup: Task<Void, Never>?

    func start(contentHandler: @escaping (UNNotificationContent) -> Void, fallback: UNMutableNotificationContent) {
        lock.withLock {
            self.contentHandler = contentHandler
            bestAttempt = fallback
        }
    }

    func setLookup(_ task: Task<Void, Never>) {
        lock.withLock { lookup = task }
    }

    func cancelLookup() {
        lock.withLock { lookup }?.cancel()
    }

    /// Applies `display` to the best attempt, if non-nil, and delivers it.
    /// Calls after the first do nothing.
    func finish(with display: NotificationDisplay?) {
        let delivery: (handler: (UNNotificationContent) -> Void, content: UNNotificationContent)? = lock.withLock {
            guard let handler = contentHandler, let content = bestAttempt else { return nil }
            if let display {
                content.title = display.title
                content.subtitle = display.subtitle
                content.body = display.body
                content.threadIdentifier = display.threadIdentifier
                content.sound = display.playsSound ? .default : nil
            }
            contentHandler = nil
            bestAttempt = nil
            lookup = nil
            return (handler, content)
        }
        guard let delivery else { return }
        delivery.handler(delivery.content)
    }
}

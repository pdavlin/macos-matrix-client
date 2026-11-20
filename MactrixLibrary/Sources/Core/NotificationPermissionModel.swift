import Foundation
import Models
import Observation
import OSLog
import UserNotifications

/// Asks macOS for permission to post notifications, once per launch, and
/// reads the permission (MATRIX-215).
///
/// One shared instance: the permission belongs to the app, not to a
/// session. `MatrixClient.startSync()` asks after a sign-in or a session
/// restore; a later sign-in does not ask again. `MatrixNotifications`
/// reads the permission before each notification, so a change in System
/// Settings applies to the next one. Settings > Notifications shows
/// `permission`.
@MainActor @Observable public final class NotificationPermissionModel {
    public static let shared = NotificationPermissionModel()

    /// The last permission that `refresh()` read.
    public private(set) var permission: NotificationPermission = .unknown

    /// The one request of this launch. Later callers wait for it.
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    /// The request of this launch threw. macOS then reports the status as
    /// not determined, but it blocks every notification.
    @ObservationIgnored private var requestFailed = false

    private init() {}

    /// Asks macOS for permission. Only the first call of a launch asks, and
    /// only it logs a refusal or a failure; later calls wait for it.
    public func requestAuthorizationOnce() async {
        if let requestTask {
            await requestTask.value
            return
        }
        let task = Task { await performRequest() }
        requestTask = task
        await task.value
    }

    /// Reads the permission from macOS into `permission`.
    ///
    /// - Returns: the permission it read.
    @discardableResult
    public func refresh() async -> NotificationPermission {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        permission = Self.permission(status: status, requestFailed: requestFailed)
        return permission
    }

    /// Maps the macOS status to the permission that Settings shows.
    ///
    /// - Parameters:
    ///   - status: `UNNotificationSettings.authorizationStatus`.
    ///   - requestFailed: the request of this launch threw.
    /// - Returns: `.blocked` when the user turned notifications off, or when
    ///   the request failed and macOS has no answer.
    nonisolated static func permission(status: UNAuthorizationStatus, requestFailed: Bool) -> NotificationPermission {
        switch status {
        case .authorized, .provisional:
            return .allowed
        #if os(iOS)
            case .ephemeral:
                return .allowed
        #endif
        case .denied:
            return .blocked
        case .notDetermined:
            return requestFailed ? .blocked : .unknown
        @unknown default:
            return .unknown
        }
    }

    private func performRequest() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if !granted {
                Logger.notification.warning("macOS does not allow notifications for this app")
            }
        } catch {
            requestFailed = true
            Logger.notification.error("notification authorization request failed: \(error)")
        }
        await refresh()
    }
}

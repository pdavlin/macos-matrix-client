import Core
import Foundation
import OSLog
import UIKit
import UserNotifications

/// MATRIX-89: asks for notification permission, registers with APNs, and
/// registers the device token as an HTTP pusher with the homeserver.
///
/// `SessionLifecycle` calls `sessionDidStart` after sign-in or restore. The
/// app delegate forwards the APNs callbacks. The two arrive in either order,
/// so the pusher call runs when both the client and the token are known.
@MainActor
final class PushRegistration {
    static let shared = PushRegistration()

    /// Weak: after sign-out, `AppState.reset()` drops the client, and no
    /// pusher call must go to it.
    private weak var client: MatrixClient?
    private var deviceToken: Data?
    /// The user id and device token of the last successful pusher call.
    private var registered: (userID: String, deviceToken: Data)?

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.davlin.matrixclient.ios", category: "push")

    /// Call when a session starts. Asks for permission (iOS shows the prompt
    /// only once), then registers with APNs.
    func sessionDidStart(_ client: MatrixClient) async {
        self.client = client
        await registerPusherIfReady()

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else {
                Self.logger.info("notification permission denied: no APNs registration")
                return
            }
        } catch {
            Self.logger.error("notification permission request failed: \(String(describing: error), privacy: .public)")
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) {
        Self.logger.info("APNs registration succeeded")
        self.deviceToken = deviceToken
        Task { await registerPusherIfReady() }
    }

    func didFailToRegister(error: any Error) {
        Self.logger.error("APNs registration failed: \(String(describing: error), privacy: .public)")
    }

    private func registerPusherIfReady() async {
        // `client.client` is nil while `MatrixClient.reset()` runs.
        guard let client, client.client != nil, let deviceToken,
              let userID = try? client.userSession().userID
        else { return }
        if let registered, registered.userID == userID, registered.deviceToken == deviceToken { return }

        do {
            try await client.registerPusher(
                deviceToken: deviceToken,
                deviceDisplayName: UIDevice.current.name,
                lang: Self.language
            )
            registered = (userID, deviceToken)
            Self.logger.info("pusher registered with \(PushGateway.url, privacy: .public)")
        } catch {
            Self.logger.error("pusher registration failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The pusher `lang`: the first preferred language, for example `en-US`.
    static var language: String {
        Locale.preferredLanguages.first ?? "en"
    }
}

/// Forwards the APNs registration callbacks to `PushRegistration`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistration.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushRegistration.shared.didFailToRegister(error: error)
    }
}

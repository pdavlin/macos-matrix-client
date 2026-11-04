import Foundation
import MatrixRustSDK
import Utils

// MARK: - Push (MATRIX-89)

/// A client for the Notification Service Extension. The `Client` is kept with
/// the notification client so that both live for the whole request.
public struct NotificationServiceClient {
    public let client: Client
    public let notificationClient: NotificationClient
}

public enum NotificationServiceClientError: Error {
    /// No App Group container: the extension cannot see the app's store.
    case noAppGroupContainer
    /// No session in the shared keychain group.
    case noSavedSession
    /// The keychain has a session, but its store folder does not exist.
    case storeMissing
}

public extension MatrixClient {
    /// Builds a client from the saved session for the Notification Service
    /// Extension. It does not start sync and does not install the app's
    /// delegates: the app process owns the sync loop.
    ///
    /// Same builder and keychain session as `attemptRestore`. Differences:
    /// - It refuses a missing store. `ClientBuilder` creates the store folder,
    ///   so an extension that builds first would make the app's
    ///   `attemptRestore` think that the store existed, and run the orphan
    ///   sweep next to an empty store.
    /// - The session delegate is `MatrixClientSessionDelegate`, so a token
    ///   refresh in the extension goes to the shared keychain.
    /// - The cross-process lock holder is the extension's (MATRIX-96), so the
    ///   store locks and the OAuth refresh lock exclude the app process.
    /// - The notification client uses `.multipleProcesses`, because the app
    ///   process can hold the same store at the same time.
    static func notificationServiceClient() async throws -> NotificationServiceClient {
        guard SessionStorageLocation.roots.isInAppGroupContainer else {
            throw NotificationServiceClientError.noAppGroupContainer
        }
        guard let userSession = try UserSession.loadUserFromKeychain() else {
            throw NotificationServiceClientError.noSavedSession
        }
        guard FileManager.default.fileExists(atPath: URL.sessionData(for: userSession.storeID).path(percentEncoded: false)) else {
            throw NotificationServiceClientError.storeMissing
        }

        let sessionDelegate = MatrixClientSessionDelegate(storeID: userSession.storeID, storePassphrase: userSession.storePassphrase)
        let client = try await clientBuilder(
            homeServer: userSession.homeserverURL,
            storeId: userSession.storeID,
            storePassphrase: userSession.storePassphrase,
            process: .notificationServiceExtension
        )
        .setSessionDelegate(sessionDelegate: sessionDelegate)
        .build()
        try await client.restoreSession(session: userSession.session)

        let notificationClient = try await client.notificationClient(processSetup: .multipleProcesses)
        return NotificationServiceClient(client: client, notificationClient: notificationClient)
    }

    /// Registers this device's HTTP pusher with the homeserver. The homeserver
    /// replaces an existing pusher with the same app id and push key, so a
    /// call on each launch is safe.
    func registerPusher(deviceToken: Data, deviceDisplayName: String, lang: String) async throws {
        // nil after `reset()`.
        guard let client else { return }
        try await client.setPusher(
            identifiers: PusherIdentifiers(
                pushkey: DeviceTokenEncoding.hexString(deviceToken),
                appId: PushGateway.pusherAppID
            ),
            kind: .http(data: HttpPusherData(
                url: PushGateway.url,
                format: .eventIdOnly,
                defaultPayload: PushGateway.defaultPayload
            )),
            appDisplayName: PushGateway.appDisplayName,
            deviceDisplayName: deviceDisplayName,
            profileTag: nil,
            lang: lang
        )
    }
}

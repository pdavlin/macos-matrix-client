import Foundation
import OSLog
import Utils

/// The identifiers that the iOS app shares with its extensions (MATRIX-88).
/// The Mac app uses none of them.
public enum AppGroup {
    /// The App Group (`com.apple.security.application-groups`). Its container
    /// holds the SDK store on iOS.
    public static let identifier = "group.io.davlin.matrixclient"

    /// The keychain access group without the App ID prefix. The entitlement is
    /// `$(AppIdentifierPrefix)io.davlin.matrixclient.shared`.
    public static let keychainAccessGroupSuffix = "io.davlin.matrixclient.shared"

    /// The `kSecAttrService` of the iOS session items. A constant, not the bundle
    /// identifier, so that an extension finds the items of the app. Its value is
    /// the iOS app's bundle identifier, the service the app used before.
    public static let keychainService = "io.davlin.matrixclient.ios"

    /// The Info.plist key that holds `$(AppIdentifierPrefix)`. Every iOS bundle
    /// that reads the session must set it.
    public static let appIdentifierPrefixInfoKey = "AppIdentifierPrefix"

    /// The full keychain access group, or `nil` if this bundle has no App ID
    /// prefix (a build without code signing).
    public static var keychainAccessGroup: String? {
        KeychainItemQuery.accessGroup(
            appIdentifierPrefix: Bundle.main.object(forInfoDictionaryKey: appIdentifierPrefixInfoKey) as? String,
            suffix: keychainAccessGroupSuffix
        )
    }
}

/// The push gateway of the iOS app (MATRIX-89). The Sygnal deployment
/// (MATRIX-90) must match these values.
public enum PushGateway {
    /// The Sygnal notify endpoint that the homeserver posts to.
    public static let url = "https://davlin-matrix.exe.xyz/_matrix/push/v1/notify"

    /// The pusher `app_id`: the Sygnal app id. The APNs topic is the app's
    /// bundle identifier, which has the same value.
    public static let pusherAppID = "io.davlin.matrixclient.ios"

    /// The pusher `default_payload`, a JSON string. See `PusherDefaultPayload`.
    public static let defaultPayload = PusherDefaultPayload.json

    /// The pusher `app_display_name`.
    public static let appDisplayName = "Mactrix"
}

/// Where the SDK store of each session lives.
public enum SessionStorageLocation {
    /// Resolves the store location now. On iOS, the first resolution logs the
    /// location, so call this at launch to put it in the log before sign-in.
    public static func resolve() {
        _ = roots
    }

    /// The store roots, resolved once per process.
    static let roots: SessionStoreRoots = {
        #if os(iOS)
            let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
        #else
            let container: URL? = nil
        #endif
        let roots = SessionStoreRoots.resolve(
            appGroupContainer: container,
            applicationSupport: .applicationSupportDirectory,
            caches: .cachesDirectory,
            applicationID: applicationID
        )
        #if os(iOS)
            if roots.isInAppGroupContainer {
                Logger.matrixClient.info(
                    """
                    session store location: App Group container \(AppGroup.identifier, privacy: .public) \
                    at \(roots.data.path(percentEncoded: false), privacy: .public)
                    """
                )
            } else {
                Logger.matrixClient.warning(
                    """
                    session store location: app container. No App Group container for \
                    \(AppGroup.identifier, privacy: .public) (no entitlement, for example an unsigned build); \
                    an extension cannot read this store at \(roots.data.path(percentEncoded: false), privacy: .public)
                    """
                )
            }
        #endif
        return roots
    }()
}

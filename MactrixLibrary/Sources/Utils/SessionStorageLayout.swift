import Foundation
import Security

/// The OS family that decides where session state lives. A value instead of
/// `#if`, so the Mac test run proves the iOS layout too.
public enum StoragePlatform: Sendable {
    case macOS
    case iOS

    public static var current: StoragePlatform {
        #if os(iOS)
            .iOS
        #else
            .macOS
        #endif
    }
}

/// The parent folders of the per-session SDK store folders.
public struct SessionStoreRoots: Equatable, Sendable {
    /// The parent of each session's data folder (`SqliteStoreBuilder.dataPath`).
    public let data: URL
    /// The parent of each session's cache folder (`SqliteStoreBuilder.cachePath`).
    public let caches: URL
    /// `true` if both roots are inside the App Group container.
    public let isInAppGroupContainer: Bool

    /// The folder name for the store roots inside the App Group container. A
    /// constant, not the bundle identifier: the app and its extensions have
    /// different bundle identifiers, but must find the same store.
    public static let appGroupFolderName = "Sessions"

    /// Returns the store roots.
    ///
    /// - `appGroupContainer` non-nil (a signed iOS build with the App Group
    ///   entitlement): `<container>/Library/Application Support/Sessions` and
    ///   `<container>/Library/Caches/Sessions`, readable by an extension.
    /// - `appGroupContainer` nil (the Mac app, or an unsigned simulator build):
    ///   `<applicationSupport>/<applicationID>` and `<caches>/<applicationID>`,
    ///   the original layout.
    public static func resolve(
        appGroupContainer: URL?,
        applicationSupport: URL,
        caches: URL,
        applicationID: String
    ) -> SessionStoreRoots {
        guard let appGroupContainer else {
            return SessionStoreRoots(
                data: applicationSupport.appending(component: applicationID),
                caches: caches.appending(component: applicationID),
                isInAppGroupContainer: false
            )
        }
        let library = appGroupContainer.appending(component: "Library")
        return SessionStoreRoots(
            data: library.appending(component: "Application Support").appending(component: appGroupFolderName),
            caches: library.appending(component: "Caches").appending(component: appGroupFolderName),
            isInAppGroupContainer: true
        )
    }
}

/// The attributes of the session keychain items, per platform.
public enum KeychainItemQuery {
    /// The attributes that identify the items of `service`.
    ///
    /// `accessGroup` applies on iOS only. The Mac app uses the legacy file-based
    /// keychain, where access groups do not apply.
    public static func base(service: String, accessGroup: String?, platform: StoragePlatform) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
        ]
        switch platform {
        case .macOS:
            /// S-27 decision: stay legacy. Data-protection mode is technically viable now
            /// (team-signed, entitlements present), but the keychain ACL's designated
            /// requirement anchors on `certificate leaf[subject.CN]`, not team ID,
            /// so grants don't survive the ~7-day cert renewal on a free personal team.
            /// Switching would add a login→data-protection migration for no net benefit.
            /// Revisit with a paid-team cert or notarized distribution. See §11 2026-09-01.
            query[kSecUseDataProtectionKeychain] = false
        case .iOS:
            if let accessGroup {
                query[kSecAttrAccessGroup] = accessGroup
            }
        }
        return query
    }

    /// The accessibility of a new item. On iOS, a Notification Service Extension
    /// must read the session while the device is locked (MATRIX-88). No iOS
    /// install predates this, so no item with the old value needs migration.
    public static func accessibility(platform: StoragePlatform) -> CFString {
        switch platform {
        case .macOS: kSecAttrAccessibleWhenUnlocked
        case .iOS: kSecAttrAccessibleAfterFirstUnlock
        }
    }

    /// The full keychain access group: the App ID prefix (`$(AppIdentifierPrefix)`,
    /// for example `ABCDE12345.`) and the group suffix. Returns `nil` if the
    /// prefix is missing or empty, for example in a build without code signing.
    public static func accessGroup(appIdentifierPrefix: String?, suffix: String) -> String? {
        guard let appIdentifierPrefix, !appIdentifierPrefix.isEmpty else { return nil }
        return appIdentifierPrefix.hasSuffix(".")
            ? appIdentifierPrefix + suffix
            : appIdentifierPrefix + "." + suffix
    }

    /// `true` if a call failed only because the build has no entitlement for the
    /// explicit access group (`errSecMissingEntitlement`, -34018). An unsigned
    /// simulator build does this. Retry without an explicit group then.
    public static func shouldRetryWithoutAccessGroup(status: OSStatus, accessGroup: String?) -> Bool {
        accessGroup != nil && status == errSecMissingEntitlement
    }
}

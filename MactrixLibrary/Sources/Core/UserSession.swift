import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog
import Security
import SwiftUI
import UI
import UniformTypeIdentifiers
import Utils

public struct UserSession: Codable {
    public let accessToken: String
    public let refreshToken: String?
    public let userID: String
    public let deviceID: String
    public let homeserverURL: String
    /// The SDK `Session.oauthData` (named `oidcData` before 26.11.11). The
    /// stored name stays, so a keychain item saved by an older build decodes.
    public let oidcData: String?
    public let storeID: String
    public let storePassphrase: String

    public init(session: Session, storeID: String, storePassphrase: String) {
        accessToken = session.accessToken
        refreshToken = session.refreshToken
        userID = session.userId
        deviceID = session.deviceId
        homeserverURL = session.homeserverUrl
        oidcData = session.oauthData
        self.storeID = storeID
        self.storePassphrase = storePassphrase
    }

    public var session: Session {
        Session(accessToken: accessToken,
                refreshToken: refreshToken,
                userId: userID,
                deviceId: deviceID,
                homeserverUrl: homeserverURL,
                oauthData: oidcData,
                slidingSyncVersion: .native)
    }

    fileprivate static var keychainKey: String { "UserSession" }

    public func saveUserToKeychain() throws {
        let keychainData = try JSONEncoder().encode(self)
        try AppKeychain().save(keychainData, forKey: Self.keychainKey)
    }

    public static func loadUserFromKeychain() throws -> Self? {
        Logger.matrixClient.debug("Load user from keychain")
        if let keychainData = try AppKeychain().load(forKey: keychainKey) {
            return try JSONDecoder().decode(Self.self, from: keychainData)
        }
        return nil
    }
}

/// The place where the session delegate keeps the user session (MATRIX-97).
/// The app uses the keychain. A test gives its own store, so no test writes
/// to the keychain items of the app.
public struct UserSessionStore: Sendable {
    public let save: @Sendable (UserSession) throws -> Void
    public let load: @Sendable () throws -> UserSession?

    public init(
        save: @escaping @Sendable (UserSession) throws -> Void,
        load: @escaping @Sendable () throws -> UserSession?
    ) {
        self.save = save
        self.load = load
    }

    public static let keychain = UserSessionStore(
        save: { try $0.saveUserToKeychain() },
        load: { try UserSession.loadUserFromKeychain() }
    )
}

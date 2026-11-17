import Foundation
import MatrixRustSDK
import OSLog
import SwiftUI
import UI
import UniformTypeIdentifiers
import Utils

/// The session delegate of a client that is not a `MatrixClient`: the sign-in
/// client on every platform (MATRIX-97) and the client of the iOS Notification
/// Service Extension (MATRIX-96).
///
/// The SDK calls `saveSessionInKeychain` only after a token refresh, so only
/// for a client that has a session. A sign-in client that has no user yet
/// writes nothing.
public final class MatrixClientSessionDelegate: MatrixRustSDK.ClientSessionDelegate {
    public let storeID: String
    public let storePassphrase: String
    private let store: UserSessionStore

    public init(storeID: String, storePassphrase: String, store: UserSessionStore = .keychain) {
        self.storeID = storeID
        self.storePassphrase = storePassphrase
        self.store = store
    }

    public func retrieveSessionFromKeychain(userId: String) throws -> MatrixRustSDK.Session {
        Logger.matrixClient.debug("client session delegate: retrieve session from keychain: \(userId, privacy: .sensitive)")

        let userSession = try store.load()
        if let userSession {
            if userSession.userID == userId {
                return userSession.session
            } else {
                Logger.matrixClient.debug(
                    "restored user session has wrong userId: \(userSession.userID, privacy: .sensitive), expected \(userId, privacy: .sensitive)"
                )
                throw MatrixClientRestoreSessionError.wrongUserId
            }
        } else {
            throw MatrixClientRestoreSessionError.sessionNotFound
        }
    }

    public func saveSessionInKeychain(session: MatrixRustSDK.Session) {
        Logger.matrixClient.debug("client session delegate: save session in keychain")
        do {
            try store.save(UserSession(session: session, storeID: storeID, storePassphrase: storePassphrase))
        } catch {
            Logger.matrixClient.error("failed to save session in keychain: \(error)")
        }
    }
}

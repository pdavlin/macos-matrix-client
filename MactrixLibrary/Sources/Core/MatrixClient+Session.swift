import Foundation
import MatrixRustSDK
import OSLog
import Security
import Utils

// MARK: - Session: build, sign-in, restore

public extension MatrixClient {
    func userSession() throws -> UserSession {
        return try UserSession(session: client.session(), storeID: storeID, storePassphrase: storePassphrase)
    }

    /// The builder of every client. On iOS it sets the cross-process lock of
    /// `process` (MATRIX-96). A multi-process client must have a session
    /// delegate, or `build()` fails.
    static func clientBuilder(
        homeServer: String,
        storeId: String,
        storePassphrase: String,
        process: ClientProcess = .app
    ) -> ClientBuilder {
        let sqliteConfig = SqliteStoreBuilder(
            dataPath: URL.sessionData(for: storeId).path(percentEncoded: false),
            cachePath: URL.sessionCaches(for: storeId).path(percentEncoded: false)
        )
        .passphrase(passphrase: storePassphrase)
        .poolMaxSize(poolMaxSize: Self.storePoolMaxSize)

        let builder = ClientBuilder()
            .serverNameOrHomeserverUrl(serverNameOrUrl: homeServer)
            .sqliteStore(config: sqliteConfig)
            .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
            .threadsEnabled(enabled: true, threadSubscriptions: true)
            .autoEnableCrossSigning(autoEnableCrossSigning: true)
            .userAgent(userAgent: ClientIdentity.current.userAgent)

        switch CrossProcessLockChoice.choice(for: process) {
        case .sdkDefault:
            return builder
        case let .multiProcess(holderName):
            return builder.crossProcessLockConfig(crossProcessLockConfig: .multiProcess(holderName: holderName))
        }
    }

    struct SecureRandomBytesError: LocalizedError {
        public let code: Int32

        public var errorDescription: String? {
            "Failed to generate secure bytes with status code \(code)"
        }
    }

    static func generateStorePassphrase() throws -> String {
        var result = [UInt8](repeating: UInt8.random(in: 0 ..< UInt8.max), count: 32)
        let status = unsafe SecRandomCopyBytes(kSecRandomDefault, result.count, &result)
        if status != errSecSuccess {
            throw SecureRandomBytesError(code: status)
        }

        return Data(result).base64EncodedString()
    }

    static func loginDetails(homeServer: String) async throws -> HomeserverLogin {
        let storeID = UUID().uuidString
        let storePassphrase = try Self.generateStorePassphrase()

        var builder = Self.clientBuilder(homeServer: homeServer, storeId: storeID, storePassphrase: storePassphrase)
        if CrossProcessLockChoice.choice(for: .app).requiresSessionDelegate {
            // This client becomes the app's client after sign-in. The delegate
            // also saves the tokens that this client refreshes.
            builder = builder.setSessionDelegate(
                sessionDelegate: MatrixClientSessionDelegate(storeID: storeID, storePassphrase: storePassphrase)
            )
        }
        let client = try await builder.build()

        let details = await client.homeserverLoginDetails()
        return HomeserverLogin(storeID: storeID, storePassphrase: storePassphrase, unauthenticatedClient: client, loginDetails: details)
    }

    static func attemptRestore() async throws -> MatrixClient? {
        guard let userSession = try UserSession.loadUserFromKeychain() else { return nil }

        // Probe the store BEFORE building the client. `ClientBuilder` creates
        // the store directory, so once the client exists the directory is
        // always present and proves nothing about whether the session's crypto
        // state was ever there.
        let storePreexisted = FileManager.default.fileExists(
            atPath: URL.sessionData(for: userSession.storeID).path(percentEncoded: false)
        )

        let matrixClient = try await MatrixClient(userSession: userSession)

        // Restore the client using the session.
        try await matrixClient.client.restoreSession(session: userSession.session)

        // `restoreSession` succeeds on an empty store: the access token and the
        // device ID come from the keychain, not from the store. So a missing
        // store yields a live session with no crypto state, and every sibling
        // directory then looks like an orphan next to it. Sweeping there
        // deletes the real store. Refuse, and leave the evidence in place for
        // a human to sort out.
        if storePreexisted {
            Self.removeOrphanedStores(keeping: userSession.storeID)
        } else {
            Logger.matrixClient.error(
                """
                session store \(userSession.storeID, privacy: .public) was missing at restore; \
                the SDK created an empty one. Skipping the orphan sweep so that no other store is \
                destroyed. Crypto state is absent: expect UTDs until the store is restored or the \
                session is replaced.
                """
            )
        }

        return matrixClient
    }

    /// Removes store directories left behind by login attempts that never
    /// completed. Safe only once a session is restored AND the restored store
    /// already existed: at that point the single-account contract means every
    /// sibling of the live store is an orphan, and no login flow is in
    /// progress. Never call this with a store the SDK just created — see
    /// `attemptRestore`.
    static func removeOrphanedStores(keeping storeID: String) {
        let parents = [
            URL.sessionData(for: storeID).deletingLastPathComponent(),
            URL.sessionCaches(for: storeID).deletingLastPathComponent(),
        ]
        for parent in parents {
            for orphan in SessionStores.orphanedDirectories(in: parent, keeping: storeID) {
                do {
                    try FileManager.default.removeItem(at: orphan)
                    Logger.matrixClient.info("removed orphaned session store \(orphan.lastPathComponent)")
                } catch {
                    Logger.matrixClient.error("failed to remove orphaned session store: \(error)")
                }
            }
        }
    }
}

public enum MatrixClientRestoreSessionError: Error {
    case sessionNotFound, wrongUserId
}

extension MatrixClient: MatrixRustSDK.ClientSessionDelegate {
    public nonisolated func retrieveSessionFromKeychain(userId: String) throws -> MatrixRustSDK.Session {
        Logger.matrixClient.debug("client session delegate: retrieve session from keychain: \(userId, privacy: .sensitive)")

        let userSession = try UserSession.loadUserFromKeychain()
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

    public nonisolated func saveSessionInKeychain(session: MatrixRustSDK.Session) {
        Logger.matrixClient.debug("client session delegate: save session in keychain")
        do {
            try UserSession(session: session, storeID: storeID, storePassphrase: storePassphrase).saveUserToKeychain()
        } catch {
            Logger.matrixClient.error("failed to save session in keychain: \(error)")
        }
    }
}

/// Internal, not private: `MatrixClient+Push` probes the store folder (MATRIX-89).
extension URL {
    static func sessionData(for sessionID: String) -> URL {
        SessionStorageLocation.roots.data.appending(component: sessionID)
    }

    static func sessionCaches(for sessionID: String) -> URL {
        SessionStorageLocation.roots.caches.appending(component: sessionID)
    }
}

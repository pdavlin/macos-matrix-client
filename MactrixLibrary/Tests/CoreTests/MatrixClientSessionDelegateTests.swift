@testable import Core
import Foundation
import MatrixRustSDK
import Testing

/// MATRIX-97: the session delegate of the sign-in client saves the tokens that
/// the client refreshes. The tests use a store in memory, not the keychain.
struct MatrixClientSessionDelegateTests {
    private final class MemoryStore: @unchecked Sendable {
        private let lock = NSLock()
        private var saved: [UserSession] = []

        var sessions: [UserSession] {
            lock.withLock { saved }
        }

        var store: UserSessionStore {
            UserSessionStore(
                save: { session in self.lock.withLock { self.saved.append(session) } },
                load: { self.lock.withLock { self.saved.last } }
            )
        }
    }

    private struct SaveFailure: Error {}

    private static func session(accessToken: String, refreshToken: String?, userId: String = "@dev:example.org") -> Session {
        Session(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: userId,
            deviceId: "DEVICE",
            homeserverUrl: "https://matrix.example.org",
            oauthData: "{\"client_id\":\"abc\"}",
            slidingSyncVersion: .native
        )
    }

    private static func delegate(_ memory: MemoryStore) -> MatrixClientSessionDelegate {
        MatrixClientSessionDelegate(storeID: "store-1", storePassphrase: "passphrase-1", store: memory.store)
    }

    @Test func aClientWithNoSessionSavesNothing() {
        let memory = MemoryStore()
        _ = Self.delegate(memory)
        #expect(memory.sessions.isEmpty)
    }

    @Test func aTokenRefreshReachesTheStore() throws {
        let memory = MemoryStore()
        let delegate = Self.delegate(memory)

        delegate.saveSessionInKeychain(session: Self.session(accessToken: "access-2", refreshToken: "refresh-2"))

        let saved = try #require(memory.sessions.last)
        #expect(memory.sessions.count == 1)
        #expect(saved.accessToken == "access-2")
        #expect(saved.refreshToken == "refresh-2")
        #expect(saved.userID == "@dev:example.org")
        #expect(saved.deviceID == "DEVICE")
        #expect(saved.homeserverURL == "https://matrix.example.org")
        #expect(saved.oidcData == "{\"client_id\":\"abc\"}")
    }

    /// The restore path opens the store with these two values.
    @Test func theSavedSessionKeepsTheStoreOfTheSignInClient() throws {
        let memory = MemoryStore()

        Self.delegate(memory).saveSessionInKeychain(session: Self.session(accessToken: "access-2", refreshToken: "refresh-2"))

        let saved = try #require(memory.sessions.last)
        #expect(saved.storeID == "store-1")
        #expect(saved.storePassphrase == "passphrase-1")
    }

    @Test func aSecondRefreshReplacesTheTokensOfTheFirst() throws {
        let memory = MemoryStore()
        let delegate = Self.delegate(memory)

        delegate.saveSessionInKeychain(session: Self.session(accessToken: "access-2", refreshToken: "refresh-2"))
        delegate.saveSessionInKeychain(session: Self.session(accessToken: "access-3", refreshToken: "refresh-3"))

        let restored = try delegate.retrieveSessionFromKeychain(userId: "@dev:example.org")
        #expect(restored.accessToken == "access-3")
        #expect(restored.refreshToken == "refresh-3")
    }

    /// The delegate method cannot throw. A failed save must not stop the client.
    @Test func aFailedSaveDoesNotThrow() {
        let delegate = MatrixClientSessionDelegate(
            storeID: "store-1",
            storePassphrase: "passphrase-1",
            store: UserSessionStore(save: { _ in throw SaveFailure() }, load: { nil })
        )

        delegate.saveSessionInKeychain(session: Self.session(accessToken: "access-2", refreshToken: "refresh-2"))
    }

    @Test func retrieveBeforeSignInThrowsSessionNotFound() {
        let delegate = Self.delegate(MemoryStore())

        #expect(throws: MatrixClientRestoreSessionError.sessionNotFound) {
            try delegate.retrieveSessionFromKeychain(userId: "@dev:example.org")
        }
    }

    @Test func retrieveForAnotherUserThrowsWrongUserId() {
        let memory = MemoryStore()
        let delegate = Self.delegate(memory)
        delegate.saveSessionInKeychain(session: Self.session(accessToken: "access-2", refreshToken: nil))

        #expect(throws: MatrixClientRestoreSessionError.wrongUserId) {
            try delegate.retrieveSessionFromKeychain(userId: "@other:example.org")
        }
    }
}

import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog
import Security
import SwiftUI
import Tokens
import UI
import UniformTypeIdentifiers
import Utils

@MainActor @Observable
public class MatrixClient {
    public let storeID: String
    public let storePassphrase: String
    public var client: ClientProtocol!

    public var rooms: [SidebarRoom] = []

    public var spaceService: LiveSpaceService? // optional, not IUO: reset() nils it before AppState detaches the client (MATRIX-51)

    private var clientDelegateHandle: TaskHandle?
    public var authenticationFailed: Bool = false

    public let notifications: MatrixNotifications = .init()

    public init(userSession: UserSession) async throws {
        storeID = userSession.storeID
        storePassphrase = userSession.storePassphrase

        client = try await Self.clientBuilder(homeServer: userSession.homeserverURL, storeId: storeID, storePassphrase: storePassphrase)
            .setSessionDelegate(sessionDelegate: self)
            .build()

        spaceService = await LiveSpaceService(spaceService: client.spaceService())
        clientDelegateHandle = try? client.setDelegate(delegate: self)
        await installUtdHook()
    }

    public init(storeID: String, storePassphrase: String, client: ClientProtocol) async {
        self.storeID = storeID
        self.storePassphrase = storePassphrase
        self.client = client

        spaceService = await LiveSpaceService(spaceService: client.spaceService())
        clientDelegateHandle = try? self.client.setDelegate(delegate: self)
        await installUtdHook()
    }

    /// Installs the UTD reporter at client creation, before any view code can
    /// run. Timelines configured with `reportUtds: true` fail to build if no
    /// hook is set, and a warm-store launch resolves a room (restored
    /// selection, or a fast click) before `startSync()` runs — ordering the
    /// hook inside `startSync` left that window open (MATRIX-61; previously
    /// MATRIX-55/56). UniFFI's handle map owns the delegate once it is
    /// lowered, so the reporter needs no strong reference here. The SDK errors
    /// if a delegate is already set, which is why this lives in the
    /// once-per-client init path and not somewhere a view can re-enter.
    private func installUtdHook() async {
        do {
            try await client.setUtdDelegate(utdDelegate: UtdReporter())
        } catch {
            Logger.matrixClient.error("failed to set UTD delegate: \(String(describing: error), privacy: .public)")
        }
    }

    public func userSession() throws -> UserSession {
        return try UserSession(session: client.session(), storeID: storeID, storePassphrase: storePassphrase)
    }

    /// The builder of every client. On iOS it sets the cross-process lock of
    /// `process` (MATRIX-96). A multi-process client must have a session
    /// delegate, or `build()` fails.
    public static func clientBuilder(
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

        let builder = ClientBuilder()
            .serverNameOrHomeserverUrl(serverNameOrUrl: homeServer)
            .sqliteStore(config: sqliteConfig)
            .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
            .threadsEnabled(enabled: true, threadSubscriptions: true)
            .autoEnableCrossSigning(autoEnableCrossSigning: true)
            .userAgent(userAgent: "Mactrix macOS")

        switch CrossProcessLockChoice.choice(for: process) {
        case .sdkDefault:
            return builder
        case let .multiProcess(holderName):
            return builder.crossProcessLockConfig(crossProcessLockConfig: .multiProcess(holderName: holderName))
        }
    }

    public struct SecureRandomBytesError: LocalizedError {
        public let code: Int32

        public var errorDescription: String? {
            "Failed to generate secure bytes with status code \(code)"
        }
    }

    public static func generateStorePassphrase() throws -> String {
        var result = [UInt8](repeating: UInt8.random(in: 0 ..< UInt8.max), count: 32)
        let status = unsafe SecRandomCopyBytes(kSecRandomDefault, result.count, &result)
        if status != errSecSuccess {
            throw SecureRandomBytesError(code: status)
        }

        return Data(result).base64EncodedString()
    }

    public static func loginDetails(homeServer: String) async throws -> HomeserverLogin {
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

    public static func attemptRestore() async throws -> MatrixClient? {
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
    public static func removeOrphanedStores(keeping storeID: String) {
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

    public func reset() async throws {
        Logger.matrixClient.debug("matrix client sign out")

        // Tear down the sync machinery BEFORE logout. Every handle below keeps
        // Rust objects alive in the FFI handle maps: an unstopped sync service
        // keeps long-polling with the token that `logout` revokes, observed
        // server-side as a ~5 req/s storm of 401s (S-30).
        roomEntriesTask?.cancel()
        roomEntriesTask = nil
        roomListEntriesHandle?.entriesStream().cancel()
        roomListEntriesHandle = nil

        roomListServiceStateHandle?.cancel()
        roomListServiceStateHandle = nil
        syncIndicatorHandle?.cancel()
        syncIndicatorHandle = nil
        syncStateHandle?.cancel()
        syncStateHandle = nil
        verificationStateHandle?.cancel()
        verificationStateHandle = nil
        recoveryStateHandle?.cancel()
        recoveryStateHandle = nil
        ignoredUsersHandle?.cancel()
        ignoredUsersHandle = nil
        clientDelegateHandle?.cancel()
        clientDelegateHandle = nil

        spaceService?.cancelSubscriptions()
        spaceService = nil

        await syncService?.stop()
        syncService = nil
        roomListService = nil
        roomListServiceState = nil
        showRoomSyncIndicator = nil
        notificationClient = nil

        try? await client.logout()
        client = nil

        try? FileManager.default.removeItem(at: .sessionData(for: storeID))
        try? FileManager.default.removeItem(at: .sessionCaches(for: storeID))
        try AppKeychain().removeAll()
        Logger.matrixClient.debug("matrix client sign out complete")
    }

    public var syncService: SyncService?
    public var syncState: SyncServiceState = .terminated
    public var roomListService: RoomListService?
    public var roomListServiceState: RoomListServiceState?
    public var showRoomSyncIndicator: RoomListServiceSyncIndicator?
    public var ignoredUserIds: [String] = []

    @ObservationIgnored private var roomEntriesTask: Task<Void, Never>?
    @ObservationIgnored fileprivate var roomListEntriesHandle: RoomListEntriesWithDynamicAdaptersResult?
    @ObservationIgnored fileprivate var roomListServiceStateHandle: TaskHandle?
    @ObservationIgnored fileprivate var syncIndicatorHandle: TaskHandle?
    @ObservationIgnored fileprivate var syncStateHandle: TaskHandle?
    @ObservationIgnored fileprivate var verificationStateHandle: TaskHandle?
    @ObservationIgnored fileprivate var recoveryStateHandle: TaskHandle?
    @ObservationIgnored fileprivate var ignoredUsersHandle: TaskHandle?

    /// The latest session verification request received by another client
    public var sessionVerificationRequest: SessionVerificationRequestDetails?
    public var sessionVerificationData: SessionVerificationData?
    public var verificationState: VerificationState?

    /// S-24: `UserIdentity.hasVerificationViolation()` for the account's own user.
    public var hasIdentityViolation: Bool = false
    /// S-24: `UserIdentity.wasPreviouslyVerified()` for the account's own user.
    public var wasPreviouslyVerified: Bool = false

    /// Whether secret storage exists on the server, and whether this device
    /// can read it. Drives the recovery UI — see `RecoveryProgress`.
    ///
    /// Reads `.unknown` until the first sync settles, so a view must treat
    /// `.unknown` as "not yet known" rather than "nothing to do".
    public var recoveryState: RecoveryState = .unknown

    public var notificationClient: NotificationClient?

    public func startSync() async throws {
        let _syncService = try await client.syncService().withOfflineMode().finish()
        syncService = _syncService

        syncStateHandle = _syncService.state(listener: self)

        let _roomListService = _syncService.roomListService()
        roomListService = _roomListService
        roomListServiceStateHandle = _roomListService.state(listener: self)
        syncIndicatorHandle = _roomListService.syncIndicator(delayBeforeShowingInMs: 200, delayBeforeHidingInMs: 200, listener: self)

        let roomEntriesListener = AsyncSDKListener<[RoomListEntriesUpdate]>()
        let _roomListEntriesHandle = try await _roomListService.allRooms().entriesWithDynamicAdapters(pageSize: 100, listener: roomEntriesListener)
        _ = _roomListEntriesHandle.controller().setFilter(kind: .all(filters: []))
        roomListEntriesHandle = _roomListEntriesHandle

        roomEntriesTask = Task { [weak self] in
            for await roomEntries in roomEntriesListener {
                guard let self else { break }
                self.updateRoomEntries(roomEntriesUpdate: roomEntries)
            }
        }

        notificationClient = try await client.notificationClient(processSetup: .singleProcess(syncService: _syncService))
        await client.registerNotificationHandler(listener: notifications)

        try await client.getSessionVerificationController().setDelegate(delegate: self)

        verificationStateHandle = client.encryption().verificationStateListener(listener: self)

        // Recovery state decides whether this device can pull the backup
        // decryption key out of secret storage. `disabled` or `incomplete`
        // means device-historical events stay undecryptable however many times
        // the device is verified by SAS. Subscribed rather than sampled: the
        // value reads `unknown` until the first sync settles.
        recoveryStateHandle = client.encryption().recoveryStateListener(listener: self)

        ignoredUsersHandle = client.subscribeToIgnoredUsers(listener: self)
        ignoredUserIds = try await client.ignoredUsers()

        // Start the sync loop.
        await _syncService.start()
        Logger.matrixClient.info("Matrix sync started")
    }

    public func clearCache() async throws {
        try await client.clearCaches(syncService: syncService)
    }

    public func isUserIgnored(_ userId: String) -> Bool {
        ignoredUserIds.contains(userId)
    }

    public func declineVerificationRequest(request: SessionVerificationRequestDetails) async throws {
        try await client.getSessionVerificationController().acknowledgeVerificationRequest(
            senderId: request.senderProfile.userId, flowId: request.flowId
        )

        try await client.getSessionVerificationController().cancelVerification()
    }

    public func acceptVerificationRequest(request: SessionVerificationRequestDetails) async throws {
        try await client.getSessionVerificationController().acknowledgeVerificationRequest(
            senderId: request.senderProfile.userId, flowId: request.flowId
        )

        try await client.getSessionVerificationController().acceptVerificationRequest()
    }

    public func requestDeviceVerification() async throws {
        try await client.getSessionVerificationController().requestDeviceVerification()
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

public extension MatrixClient {
    // In-memory cache of decoded image objects. Purpose is rendering performance —
    // keeping decoded bitmaps ready to display prevents flicker when scrolling back to
    // previously viewed images. This is distinct from the SDK-level media download cache
    // (see clearCaches / getMediaFile(useCache:)) which avoids re-fetching from the server.
    // Costs are tracked in decoded RGBA bytes (width × height × 4), not compressed sizes,
    // since a typical JPEG can be 20-50× larger once decoded.
    static let imageCache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.totalCostLimit = 256 * 1024 * 1024 // 256MB decoded pixels
        return cache
    }()

    private static let imageCacheMaxObjectCost = 64 * 1024 * 1024 // 64MB per object (~8000x2000px RGBA)

    static func setCachedImage(_ image: PlatformImage, forKey key: NSString) {
        let cost = Int(image.size.width * image.size.height) * 4 // decoded RGBA bytes
        guard cost <= imageCacheMaxObjectCost else { return }
        imageCache.setObject(image, forKey: key, cost: cost)
    }
}

public extension MatrixClient {
    struct MatrixClientUserProfileActions: UserProfileActions {
        public let userId: String
        public let matrixClient: MatrixClient
        public let windowState: WindowState

        public func sendMessage() async {
            do {
                if let room = try matrixClient.client.getDmRoom(userId: userId) {
                    windowState.selectedRoomId = room.id
                    return
                }

                let createRoomParams = CreateRoomParameters(
                    name: nil, isEncrypted: false, isDirect: true, visibility: .private,
                    preset: .privateChat, invite: [userId]
                )
                let roomId = try await matrixClient.client.createRoom(request: createRoomParams)
                windowState.selectedRoomId = roomId
            } catch {
                Logger.viewCycle.error("failed to get DM room for user \(userId): \(error)")
            }
        }

        public func shareProfile() {}

        public func ignoreUser() async {
            Logger.viewCycle.info("Ignore user \(userId)")
            do {
                try await matrixClient.client.ignoreUser(userId: userId)
            } catch {
                Logger.viewCycle.error("failed to ignore user: \(error)")
            }
        }

        public func unignoreUser() async {
            Logger.viewCycle.info("Unignore user \(userId)")
            do {
                try await matrixClient.client.unignoreUser(userId: userId)
            } catch {
                Logger.viewCycle.error("failed to unignore user: \(error)")
            }
        }
    }

    func userProfileActions(forUserId userId: String, windowState: WindowState) -> some UserProfileActions {
        return MatrixClientUserProfileActions(userId: userId, matrixClient: self, windowState: windowState)
    }
}

public extension MatrixClient {
    @MainActor
    struct MatrixClientRoomPreviewActions: @MainActor RoomPreviewActions {
        public let roomId: String
        public let matrixClient: MatrixClient
        public let windowState: WindowState

        public func joinRoom() async throws {
            let room = try await matrixClient.client.joinRoomById(roomId: roomId)
            let timeline = LiveTimeline(room: LiveRoom(matrixRoom: room))
            windowState.selectedScreen = .joinedRoom(timeline: timeline)
        }

        public func knockRoom() async throws {
            let room = try await matrixClient.client.knock(roomIdOrAlias: roomId, reason: nil, serverNames: ["matrix.org"])
            let timeline = LiveTimeline(room: LiveRoom(matrixRoom: room))
            windowState.selectedScreen = .joinedRoom(timeline: timeline)
        }

        public func visitRoom() {
            windowState.selectedRoomId = roomId
        }
    }

    func roomPreviewActions(forRoomWithId roomId: String, windowState: WindowState) -> RoomPreviewActions {
        return MatrixClientRoomPreviewActions(roomId: roomId, matrixClient: self, windowState: windowState)
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

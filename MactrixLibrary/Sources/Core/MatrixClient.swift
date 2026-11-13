import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import Models
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

    /// Internal, not private: `reset()` in `MatrixClient+Sync.swift` cancels it.
    var clientDelegateHandle: TaskHandle?
    public var authenticationFailed: Bool = false

    public let notifications: MatrixNotifications = .init()

    /// MATRIX-119: the Dock badge and the account-wide unread chat count.
    public let dockBadge = DockBadgeController()

    /// The account's recent emoji for this session (MATRIX-111). See
    /// `MatrixClient+RecentEmoji.swift`.
    public let recentEmojis = RecentEmojiStore()

    /// MATRIX-155: the custom emoji of the open chats' workspaces. See
    /// `MatrixClient+ImagePacks.swift`.
    public let imagePacks = ImagePackStore()

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

    public var syncService: SyncService?
    public var syncState: SyncServiceState = .terminated
    public var roomListService: RoomListService?
    public var roomListServiceState: RoomListServiceState?
    public var showRoomSyncIndicator: RoomListServiceSyncIndicator?
    public var ignoredUserIds: [String] = []

    // Internal, not private: `startSync()` and `reset()` in `MatrixClient+Sync.swift`
    // set and cancel these handles.
    @ObservationIgnored var roomEntriesTask: Task<Void, Never>?
    @ObservationIgnored var roomListEntriesHandle: RoomListEntriesWithDynamicAdaptersResult?
    @ObservationIgnored var roomListServiceStateHandle: TaskHandle?
    @ObservationIgnored var syncIndicatorHandle: TaskHandle?
    @ObservationIgnored var syncStateHandle: TaskHandle?
    @ObservationIgnored var verificationStateHandle: TaskHandle?
    @ObservationIgnored var recoveryStateHandle: TaskHandle?
    @ObservationIgnored var ignoredUsersHandle: TaskHandle?

    /// The latest session verification request received by another client
    public var sessionVerificationRequest: SessionVerificationRequestDetails?
    public var sessionVerificationData: MatrixRustSDK.SessionVerificationData?
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

    /// MATRIX-77: the account's chat labels. Created when sync starts.
    public var labels: LabelsModel?

    /// MATRIX-140: the account's merged chats. Created when sync starts,
    /// refreshed on the same triggers as `labels`.
    public var mergedChats: MergedChatsModel?

    /// MATRIX-147: the space names that tell merged-chat members apart.
    public let roomAccounts = RoomAccountNames()

    /// MATRIX-67: the chat-list filter the sidebar last chose.
    ///
    /// The entries controller belongs to the client, not to a window, so the
    /// sidebar re-applies its window's choice whenever that window becomes
    /// active, and the most recently active window's filter is the one shown.
    @ObservationIgnored public private(set) var chatListFilter: ChatListFilter = .inbox

    /// MATRIX-77: the rooms of the label the sidebar last selected, or nil
    /// for the Inbox. Applied with `chatListFilter`, per client like it.
    @ObservationIgnored public private(set) var chatListLabelRooms: [String]?

    /// Applies `filter`, narrowed to `labelRooms` when a label is selected,
    /// to the room-list entries. A no-op when it is already applied: every
    /// `setFilter` resets the list, and each reset re-fetches every row's
    /// room info and latest event.
    public func setChatListFilter(_ filter: ChatListFilter, labelRooms: [String]? = nil) {
        guard filter != chatListFilter || labelRooms != chatListLabelRooms else { return }
        chatListFilter = filter
        chatListLabelRooms = labelRooms
        // Before `startSync()` there is no handle yet; it picks up
        // `chatListFilter` when it creates one.
        guard let controller = roomListEntriesHandle?.controller() else { return }
        if !controller.setFilter(kind: filter.roomListFilter(labelRooms: labelRooms)) {
            Logger.matrixClient.error("room list rejected filter \(filter.rawValue, privacy: .public)")
        }
    }

    public func isUserIgnored(_ userId: String) -> Bool {
        ignoredUserIds.contains(userId)
    }
}

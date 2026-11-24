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

    /// MATRIX-163: the account's global profile avatar, an `mxc://` URL. The
    /// one value every own avatar draws from. See
    /// `MatrixClient+OwnProfile.swift`.
    public internal(set) var ownAvatarUrl: String?

    /// MATRIX-165: the avatar of the user's own bridge ghost, by workspace.
    /// See `MatrixClient+OwnServiceProfile.swift`.
    public let ownServiceAvatars = OwnServiceAvatarStore()

    /// MATRIX-224: the saved composer drafts, for the "Draft:" row prefix
    /// and the Drafts list filter.
    public let composerDrafts = ChatListDraftsModel()

    /// MATRIX-224: the typing state of the chat-list rows on the screen.
    public let chatListTyping = ChatListTypingModel()

    public init(userSession: UserSession) async throws {
        storeID = userSession.storeID
        storePassphrase = userSession.storePassphrase
        restoreSpaceLaunchCache()

        client = try await Self.clientBuilder(homeServer: userSession.homeserverURL, storeId: storeID, storePassphrase: storePassphrase)
            .setSessionDelegate(sessionDelegate: self)
            .build()

        spaceService = await LiveSpaceService(spaceService: client.spaceService())
        followJoinedSpaces()
        configureMusicLinkTitles()
        clientDelegateHandle = try? client.setDelegate(delegate: self)
        await installUtdHook()
    }

    public init(storeID: String, storePassphrase: String, client: ClientProtocol) async {
        self.storeID = storeID
        self.storePassphrase = storePassphrase
        self.client = client
        restoreSpaceLaunchCache()

        spaceService = await LiveSpaceService(spaceService: client.spaceService())
        followJoinedSpaces()
        configureMusicLinkTitles()
        clientDelegateHandle = try? self.client.setDelegate(delegate: self)
        await installUtdHook()
    }

    /// MATRIX-170: the last session's space data, before any SDK answer, so
    /// the rail, the workspace icons and a restored space filter are right
    /// in the first frame.
    private func restoreSpaceLaunchCache() {
        roomAccounts.restore(cacheFile: SpaceLaunchCache.file(in: URL.sessionCaches(for: storeID)))
    }

    /// MATRIX-170: the live list of joined spaces replaces the cached list.
    private func followJoinedSpaces() {
        guard let spaceService else { return }
        roomAccounts.attach(spaces: spaceService)
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
    public internal(set) var syncState: SyncServiceState = .terminated
    /// MATRIX-237: whether the sync service sent `running` at least once.
    /// After that, `idle` means that sync stopped, not that it connects.
    public internal(set) var syncHasRun = false
    /// MATRIX-237: whether the last `startSync()` threw. The sync state
    /// can then stay `idle` with no service that runs.
    public internal(set) var syncStartFailed = false
    /// The sidebar's sync line for the current sync state.
    public var syncStatusLine: SyncStatusLine {
        SyncStatusLine(state: syncState, hasRun: syncHasRun, startFailed: syncStartFailed)
    }

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
    /// MATRIX-237: the tasks that apply the SDK listener values above, in
    /// order. See `AsyncSDKListener.deliver(to:)`.
    @ObservationIgnored var listenerTasks: [Task<Void, Never>] = []
    /// MATRIX-237: whether `syncService` was started. A second `startSync()`
    /// then restarts it and does not build a second service.
    @ObservationIgnored var syncServiceStarted = false

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

    /// MATRIX-206: the account's inbox states (archived, snoozed, reminders).
    public var inbox: InboxStateModel?
    /// MATRIX-208: the account's bookmarked messages. Created when sync
    /// starts, refreshed on the same triggers as `labels`.
    public var bookmarks: BookmarksModel?
    /// MATRIX-212: the account's scheduled messages (Send Later). Created
    /// when sync starts, refreshed on the same triggers as `labels`.
    public var scheduledMessages: ScheduledMessagesModel?

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

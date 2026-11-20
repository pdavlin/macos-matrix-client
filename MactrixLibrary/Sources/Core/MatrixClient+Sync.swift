import Foundation
import MatrixRustSDK
import Models
import OSLog

// MARK: - Sync lifecycle: start, clear caches, sign-out teardown

public extension MatrixClient {
    func startSync() async throws {
        let _syncService = try await client.syncService().withOfflineMode().finish()
        syncService = _syncService

        syncStateHandle = _syncService.state(listener: self)

        let _roomListService = _syncService.roomListService()
        roomListService = _roomListService
        roomListServiceStateHandle = _roomListService.state(listener: self)
        syncIndicatorHandle = _roomListService.syncIndicator(delayBeforeShowingInMs: 200, delayBeforeHidingInMs: 200, listener: self)

        let roomEntriesListener = AsyncSDKListener<[RoomListEntriesUpdate]>()
        let _roomListEntriesHandle = try await _roomListService.allRooms().entriesWithDynamicAdapters(pageSize: 100, listener: roomEntriesListener)
        _ = _roomListEntriesHandle.controller().setFilter(kind: chatListFilter.roomListFilter(labelRooms: chatListLabelRooms))
        roomListEntriesHandle = _roomListEntriesHandle

        roomEntriesTask = Task { [weak self] in
            for await roomEntries in roomEntriesListener {
                guard let self else { break }
                self.updateRoomEntries(roomEntriesUpdate: roomEntries)
            }
        }

        notificationClient = try await client.notificationClient(processSetup: .singleProcess(syncService: _syncService))
        await client.registerNotificationHandler(listener: notifications)
        // MATRIX-215: ask for notification permission once per launch, after
        // a sign-in or a session restore. Not awaited: macOS can show a
        // prompt, and sync must not wait for the user.
        Task { await NotificationPermissionModel.shared.requestAuthorizationOnce() }

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

        // MATRIX-77: labels read the local store, so this first read shows
        // what the last session synced; the room list's `running` state
        // re-reads once sync catches up.
        if labels == nil {
            labels = LabelsModel(client: client, notifications: notifications)
        }
        await labels?.refresh()

        // MATRIX-140: merged chats are read the same way as labels.
        if mergedChats == nil {
            mergedChats = MergedChatsModel(client: client)
        }
        await mergedChats?.refresh()

        // MATRIX-208: bookmarks are read the same way.
        if bookmarks == nil {
            bookmarks = BookmarksModel(client: client)
        }
        await bookmarks?.refresh()

        // MATRIX-144 hookup (MATRIX-141 Phase B): notifications and the Dock
        // badge read the merged chats live. The badge reads the observable
        // document inside Observation tracking, so a merge or an unmerge
        // recomputes it. After a sign-out `mergedChats` is nil: no merges.
        notifications.mergedChats = { [weak self] in self?.mergedChats?.document ?? MergedChatDocument() }
        dockBadge.mergedChats = { [weak self] in self?.mergedChats?.document ?? MergedChatDocument() }

        // MATRIX-206: inbox states are read the same way. Archived chats do
        // not count in the Dock badge, and the tracker's unread changes
        // drive the rule that moves a chat back to the Inbox.
        if inbox == nil {
            let model = InboxStateModel(client: client) { [weak self] in
                self?.mergedChats?.document ?? MergedChatDocument()
            }
            model.startWatching(dockBadge.unreadChats)
            inbox = model
        }
        await inbox?.refresh()
        dockBadge.inboxHiddenRoomIds = { [weak self] in self?.inbox?.hiddenRoomIds ?? [] }

        // MATRIX-119: a no-op on iOS. Restart sync calls this again with
        // the new room list service.
        await dockBadge.start(roomListService: _roomListService, labels: labels)

        // MATRIX-163: read the account's profile avatar. Not awaited: the
        // read is a server request and must not hold the sync start.
        Task { [weak self] in await self?.refreshOwnAvatar(readsCache: true) }

        // Start the sync loop.
        await _syncService.start()
        Logger.matrixClient.info("Matrix sync started")
    }

    func clearCache() async throws {
        try await client.clearCaches(syncService: syncService)
    }

    func reset() async throws {
        Logger.matrixClient.debug("matrix client sign out")

        // Tear down the sync machinery BEFORE logout. Every handle below keeps
        // Rust objects alive in the FFI handle maps: an unstopped sync service
        // keeps long-polling with the token that `logout` revokes, observed
        // server-side as a ~5 req/s storm of 401s (S-30).
        roomEntriesTask?.cancel()
        roomEntriesTask = nil
        roomListEntriesHandle?.entriesStream().cancel()
        roomListEntriesHandle = nil

        // MATRIX-119: drop the per-room subscriptions and clear the badge.
        dockBadge.stop()

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
        // MATRIX-170: no cache write after the cache folder is removed.
        await roomAccounts.stop()
        // MATRIX-191: the same for the music link titles.
        await resetMusicLinkTitles()

        await syncService?.stop()
        syncService = nil
        roomListService = nil
        roomListServiceState = nil
        showRoomSyncIndicator = nil
        notificationClient = nil
        labels = nil
        mergedChats = nil
        inbox?.stopDueTimer()
        inbox = nil
        bookmarks = nil

        try? await client.logout()
        client = nil

        try? FileManager.default.removeItem(at: .sessionData(for: storeID))
        try? FileManager.default.removeItem(at: .sessionCaches(for: storeID))
        try AppKeychain().removeAll()
        Logger.matrixClient.debug("matrix client sign out complete")
    }
}

import Foundation
import MatrixRustSDK
import Models
import OSLog

// MARK: - Sync lifecycle: start, clear caches, sign-out teardown

public extension MatrixClient {
    /// Starts sync, or restarts it when it was started before.
    ///
    /// MATRIX-237: the sidebar's "Restart sync" calls this again. A started
    /// service is restarted with `SyncService.start()`, which the SDK makes
    /// safe to call again: it restarts an `offline` service and starts an
    /// `idle`, `terminated` or `error` one. A second service is never built:
    /// the first one would keep its sync loop but lose its state listener,
    /// so the line showed "Connecting…" while messages came in.
    func startSync() async throws {
        syncStartFailed = false
        if let syncService, syncServiceStarted {
            // The homeserver rejected the token: a restart would only retry
            // it. The session teardown follows.
            guard !authenticationFailed else { return }
            Logger.matrixClient.info("restarting sync")
            await syncService.start()
            return
        }
        do {
            try await buildAndStartSync()
        } catch {
            syncStartFailed = true
            throw error
        }
    }

    /// Cancels the tasks that apply the SDK listener values.
    internal func cancelListenerTasks() {
        roomEntriesTask?.cancel()
        roomEntriesTask = nil
        for task in listenerTasks {
            task.cancel()
        }
        listenerTasks.removeAll()
    }

    private func buildAndStartSync() async throws {
        // A service that an earlier call built did not start, so nothing
        // syncs with it. Its listener tasks go with it.
        cancelListenerTasks()

        let _syncService = try await client.syncService().withOfflineMode().finish()
        syncService = _syncService

        let _roomListService = _syncService.roomListService()
        roomListService = _roomListService
        subscribeToSyncStates(of: _syncService, roomListService: _roomListService)

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

        try await subscribeToAccountStates()

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

        // MATRIX-212: the scheduled messages are read the same way. Their
        // text stays in a file in this session's data folder.
        if scheduledMessages == nil {
            scheduledMessages = ScheduledMessagesModel(
                transport: LiveScheduledMessageTransport(client: client),
                previewStore: ScheduledMessagePreviewStore(
                    file: URL.sessionData(for: storeID).appending(component: "ScheduledMessagePreviews.json")
                )
            )
        }
        await scheduledMessages?.refresh()

        // MATRIX-144 hookup (MATRIX-141 Phase B): notifications and the Dock
        // badge read the merged chats live. The badge reads the observable
        // document inside Observation tracking, so a merge or an unmerge
        // recomputes it. After a sign-out `mergedChats` is nil: no merges.
        notifications.mergedChats = { [weak self] in self?.mergedChats?.document ?? MergedChatDocument() }
        dockBadge.mergedChats = { [weak self] in self?.mergedChats?.document ?? MergedChatDocument() }
        // MATRIX-221: Reply, Mark as Read, and Remind in 1 Hour on a
        // notification.
        notifications.actionPerformer = LiveNotificationActions(client: self)

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

        // MATRIX-119: a no-op on iOS. Restart sync keeps the room list
        // service (MATRIX-237), so this runs once for each service.
        await dockBadge.start(roomListService: _roomListService, labels: labels)

        // MATRIX-224: read the saved drafts one time, off the main actor.
        // The composer keeps the cache current after that.
        composerDrafts.loadAll(rooms: client.rooms())

        // MATRIX-163: read the account's profile avatar. Not awaited: the
        // read is a server request and must not hold the sync start.
        Task { [weak self] in await self?.refreshOwnAvatar(readsCache: true) }

        // Start the sync loop.
        await _syncService.start()
        syncServiceStarted = true
        Logger.matrixClient.info("Matrix sync started")
    }

    /// MATRIX-237: the sync service and room list states. Each listener
    /// feeds one ordered stream, see `AsyncSDKListener.deliver(to:)`.
    private func subscribeToSyncStates(of syncService: SyncService, roomListService: RoomListService) {
        let syncStateListener = AsyncSDKListener<SyncServiceState>()
        listenerTasks.append(syncStateListener.deliver { [weak self] in self?.applySyncState($0) })
        syncStateHandle = syncService.state(listener: syncStateListener)

        let roomListStateListener = AsyncSDKListener<RoomListServiceState>()
        listenerTasks.append(roomListStateListener.deliver { [weak self] in self?.applyRoomListState($0) })
        roomListServiceStateHandle = roomListService.state(listener: roomListStateListener)

        let syncIndicatorListener = AsyncSDKListener<RoomListServiceSyncIndicator>()
        listenerTasks.append(syncIndicatorListener.deliver { [weak self] in self?.applySyncIndicator($0) })
        syncIndicatorHandle = roomListService.syncIndicator(
            delayBeforeShowingInMs: 200,
            delayBeforeHidingInMs: 200,
            listener: syncIndicatorListener
        )
    }

    /// MATRIX-237: the session verification, verification, recovery and
    /// ignored users states, each through one ordered stream.
    private func subscribeToAccountStates() async throws {
        let sessionVerificationListener = AsyncSDKListener<SessionVerificationEvent>()
        listenerTasks.append(sessionVerificationListener.deliver { [weak self] in self?.applySessionVerification($0) })
        try await client.getSessionVerificationController().setDelegate(delegate: sessionVerificationListener)

        let verificationStateListener = AsyncSDKListener<VerificationState>()
        listenerTasks.append(verificationStateListener.deliver { [weak self] in await self?.applyVerificationState($0) })
        verificationStateHandle = client.encryption().verificationStateListener(listener: verificationStateListener)

        // Recovery state decides whether this device can pull the backup
        // decryption key out of secret storage. `disabled` or `incomplete`
        // means device-historical events stay undecryptable however many times
        // the device is verified by SAS. Subscribed rather than sampled: the
        // value reads `unknown` until the first sync settles.
        let recoveryStateListener = AsyncSDKListener<RecoveryState>()
        listenerTasks.append(recoveryStateListener.deliver { [weak self] in self?.applyRecoveryState($0) })
        recoveryStateHandle = client.encryption().recoveryStateListener(listener: recoveryStateListener)

        let ignoredUsersListener = AsyncSDKListener<[String]>()
        listenerTasks.append(ignoredUsersListener.deliver { [weak self] in self?.applyIgnoredUsers($0) })
        ignoredUsersHandle = client.subscribeToIgnoredUsers(listener: ignoredUsersListener)
        // MATRIX-237: a server request. Offline it throws, and a throw here
        // left a built service that never started. The subscription above
        // sends the list when it changes.
        do {
            ignoredUserIds = try await client.ignoredUsers()
        } catch {
            Logger.matrixClient.error("failed to read ignored users: \(String(describing: error), privacy: .public)")
        }
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
        cancelListenerTasks()
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
        syncServiceStarted = false
        roomListService = nil
        roomListServiceState = nil
        showRoomSyncIndicator = nil
        notificationClient = nil
        notifications.actionPerformer = nil
        labels = nil
        mergedChats = nil
        inbox?.stopDueTimer()
        inbox = nil
        bookmarks = nil
        scheduledMessages?.stop()
        scheduledMessages = nil
        // MATRIX-224.
        composerDrafts.reset()
        chatListTyping.reset()
        OwnReactionMarks.shared.removeAll()

        try? await client.logout()
        client = nil

        try? FileManager.default.removeItem(at: .sessionData(for: storeID))
        try? FileManager.default.removeItem(at: .sessionCaches(for: storeID))
        try AppKeychain().removeAll()
        Logger.matrixClient.debug("matrix client sign out complete")
    }
}

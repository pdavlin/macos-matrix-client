import Foundation
import MatrixRustSDK
import Models
import OSLog

public extension MatrixClient {
    /// A compact, greppable summary of a room-list batch.
    ///
    /// Separate from `updateRoomEntries` to keep that function under the
    /// cyclomatic complexity limit, and because the batch contents are the
    /// thing worth reading when the sidebar is empty: a lone `reset(0)` means
    /// the SDK's list is genuinely empty, not that the app mishandled an
    /// update.
    static func describe(_ updates: [RoomListEntriesUpdate]) -> String {
        updates.map { update in
            switch update {
            case let .append(values): "append(\(values.count))"
            case .clear: "clear"
            case .pushFront: "pushFront"
            case .pushBack: "pushBack"
            case .popFront: "popFront"
            case .popBack: "popBack"
            case let .insert(index, _): "insert(@\(index))"
            case let .set(index, _): "set(@\(index))"
            case let .remove(index): "remove(@\(index))"
            case let .truncate(length): "truncate(\(length))"
            case let .reset(values): "reset(\(values.count))"
            }
        }.joined(separator: ", ")
    }

    func updateRoomEntries(roomEntriesUpdate: [RoomListEntriesUpdate]) {
        Logger.matrixClient.info(
            """
            room entries update: [\(Self.describe(roomEntriesUpdate), privacy: .public)] \
            rooms before=\(self.rooms.count, privacy: .public)
            """
        )
        for update in roomEntriesUpdate {
            switch update {
            case let .append(values):
                self.rooms.append(contentsOf: values.map(SidebarRoom.init(room:)))
            case .clear:
                self.rooms.removeAll()
            case let .pushFront(room):
                self.rooms.insert(SidebarRoom(room: room), at: 0)
            case let .pushBack(room):
                self.rooms.append(SidebarRoom(room: room))
            case .popFront:
                self.rooms.removeFirst()
            case .popBack:
                self.rooms.removeLast()
            case let .insert(index, room):
                self.rooms.insert(SidebarRoom(room: room), at: Int(index))
            case let .set(index, room):
                let existing = self.rooms[Int(index)]
                if existing.id == room.id() {
                    existing.updateRoom(room)
                } else {
                    self.rooms[Int(index)] = SidebarRoom(room: room)
                }
            case let .remove(index):
                self.rooms.remove(at: Int(index))
            case let .truncate(length):
                self.rooms.removeSubrange(Int(length) ..< self.rooms.count)
            case let .reset(values: values):
                let existingById = Dictionary(self.rooms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                self.rooms = values.map { room in
                    if let existing = existingById[room.id()] {
                        existing.updateRoom(room)
                        return existing
                    }
                    return SidebarRoom(room: room)
                }
            }
        }
    }
}

// MARK: - SDK listener values (MATRIX-237)

// `startSync()` registers an `AsyncSDKListener` for each SDK listener and
// applies its values here, through `AsyncSDKListener.deliver(to:)`: one
// ordered stream with one consumer each. One `Task` per callback had no order,
// so an older value could land last.

extension MatrixClient {
    /// Applies one sync service state.
    func applySyncState(_ state: MatrixRustSDK.SyncServiceState) {
        let name = switch state {
        case .idle: "idle"
        case .running: "running"
        case .terminated: "terminated"
        case .error: "error"
        case .offline: "offline"
        }
        Logger.matrixClient.info("sync state: \(name, privacy: .public)")
        syncState = state
        if state == .running {
            syncHasRun = true
        }
    }

    /// Applies one verification state.
    func applyVerificationState(_ status: MatrixRustSDK.VerificationState) async {
        // Recorded because a session that reports `unverified` on every
        // launch cannot read the key backup, which shows up downstream as
        // `historicalMessageAndDeviceIsUnverified` UTDs rather than as
        // anything that names verification.
        let name = switch status {
        case .unknown: "unknown"
        case .verified: "verified"
        case .unverified: "unverified"
        }
        Logger.matrixClient.info("verification state: \(name, privacy: .public)")
        verificationState = status

        // S-24: check whether the account's own identity was reset
        // externally. `hasVerificationViolation()` is the SDK's signal
        // that a previously-verified identity no longer matches. Awaited in
        // the ordered stream, so an older check cannot write its result last.
        await checkOwnIdentityViolation()
    }

    /// Queries the SDK for the account's own identity violation state.
    ///
    /// Called when `verificationState` changes. The SDK's
    /// `UserIdentity.hasVerificationViolation()` reports `true` when the
    /// identity was previously verified but no longer is — the exact signal
    /// for an own-identity reset (e.g. from Element Web).
    private func checkOwnIdentityViolation() async {
        // Capture the client reference before any await: `reset()` can nil it
        // out while a verification-state callback is still queued, and this is
        // the one listener task that dereferences `client`.
        guard let client = client else { return }
        do {
            guard let userId = try? client.userId() else {
                Logger.matrixClient.warning("cannot check identity violation: userId unavailable")
                return
            }
            if let identity = try await client.encryption().userIdentity(userId: userId, fallbackToServer: true) {
                let violation = identity.hasVerificationViolation()
                let previouslyVerified = identity.wasPreviouslyVerified()
                Logger.matrixClient.info(
                    "own identity: violation=\(violation, privacy: .public) previouslyVerified=\(previouslyVerified, privacy: .public)"
                )
                hasIdentityViolation = violation
                wasPreviouslyVerified = previouslyVerified
            } else {
                Logger.matrixClient.info("own identity: userIdentity returned nil")
                hasIdentityViolation = false
                wasPreviouslyVerified = false
            }
        } catch {
            Logger.matrixClient.error("failed to check own identity violation: \(error)")
        }
    }

    /// Applies one recovery state.
    func applyRecoveryState(_ status: MatrixRustSDK.RecoveryState) {
        let name = switch status {
        case .unknown: "unknown"
        case .enabled: "enabled"
        case .disabled: "disabled"
        case .incomplete: "incomplete"
        }
        Logger.matrixClient.info("recovery state: \(name, privacy: .public)")
        recoveryState = status
    }

    /// Applies one room list service state.
    func applyRoomListState(_ state: MatrixRustSDK.RoomListServiceState) {
        // Logged because this state gates the recovery UI (see
        // `RecoveryPrompt`) and because an empty sidebar is otherwise
        // indistinguishable from a room list that never started.
        let (name, evidence): (String, SessionSyncEvidence.RoomListState) = switch state {
        case .initial: ("initial", .initial)
        case .settingUp: ("settingUp", .settingUp)
        case .recovering: ("recovering", .recovering)
        case .running: ("running", .running)
        case .error: ("error", .error)
        case .terminated: ("terminated", .terminated)
        }
        Logger.matrixClient.info("room list state: \(name, privacy: .public) rooms=\(self.rooms.count, privacy: .public)")
        roomListServiceState = state
        // MATRIX-171, MATRIX-186: an empty space graph counts only
        // after a sync (`running`).
        roomAccounts.note(roomListState: evidence)
        // MATRIX-77, MATRIX-140, MATRIX-208, MATRIX-212: sync has caught
        // up, so the labels, merged chats, bookmarks, and scheduled
        // messages in the store are current. Not awaited: each refresh
        // reads the store again, and a slow one must not hold the next
        // state.
        if case .running = state {
            Task { [weak self] in await self?.refreshAfterRoomListCaughtUp() }
        }
    }

    private func refreshAfterRoomListCaughtUp() async {
        await labels?.refresh()
        await mergedChats?.refresh()
        await inbox?.refresh()
        await bookmarks?.refresh()
        await scheduledMessages?.refresh()
        // MATRIX-207: snooze ends and reminders fire once sync has
        // caught up, so the first arm resolves what came due while
        // the app was closed against current state. macOS only: the
        // iOS UI is out of scope, and two devices would both post.
        #if os(macOS)
            inbox?.startDueTimer { [weak self] title, body, roomId in
                guard let notifications = self?.notifications else { return }
                Task { await notifications.postLocalNotification(title: title, body: body, roomId: roomId) }
            }
        #endif
    }

    /// Applies one room list sync indicator.
    func applySyncIndicator(_ syncIndicator: MatrixRustSDK.RoomListServiceSyncIndicator) {
        showRoomSyncIndicator = syncIndicator
    }

    /// Applies one ignored users list.
    func applyIgnoredUsers(_ ignoredUserIds: [String]) {
        Logger.matrixClient.debug("Updated ignored users: \(ignoredUserIds)")
        self.ignoredUserIds = ignoredUserIds
    }

    /// Applies one session verification callback.
    func applySessionVerification(_ event: SessionVerificationEvent) {
        switch event {
        case let .receivedRequest(details):
            Logger.matrixClient.debug("session verification: didReceiveVerificationRequest")
            sessionVerificationRequest = details
        case .acceptedRequest:
            Logger.matrixClient.debug("session verification: didAcceptVerificationRequest")
        case .startedSas:
            Logger.matrixClient.debug("session verification: didStartSasVerification")
        case let .receivedData(data):
            Logger.matrixClient.debug("session verification: didReceiveVerificationData")
            sessionVerificationData = data
        case .failed:
            Logger.matrixClient.debug("session verification: didFail")
            sessionVerificationRequest = nil
            sessionVerificationData = nil
        case .cancelled:
            Logger.matrixClient.debug("session verification: didCancel")
            sessionVerificationRequest = nil
            sessionVerificationData = nil
        case .finished:
            Logger.matrixClient.debug("session verification: didFinish")
            sessionVerificationRequest = nil
            sessionVerificationData = nil
        }
    }
}

extension MatrixClient: MatrixRustSDK.ClientDelegate {
    public nonisolated func onBackgroundTaskErrorReport(taskName: String, error: MatrixRustSDK.BackgroundTaskFailureReason) {
        // Both fields public: a task name and a failure reason are diagnostics,
        // not secrets, and the redacted version of this line was useless while
        // chasing an empty room list.
        Logger.matrixClient.error(
            "background task failed: \(taskName, privacy: .public) reason=\(String(describing: error), privacy: .public)"
        )
    }

    public nonisolated func didReceiveAuthError(isSoftLogout: Bool) {
        Task { @MainActor in
            if isSoftLogout {
                Logger.matrixClient.debug("did receive auth error: soft logout true")
                return
            }
            // The sync machinery keeps retrying the rejected token, so this
            // callback re-fires several times per second until sync stops
            // (observed ~7/s, MATRIX-48). Only the first callback may act,
            // and it must stop sync itself: the observer that tears down the
            // session runs later on the main queue, and every retry until
            // then hammers the homeserver.
            guard !authenticationFailed else { return }
            authenticationFailed = true
            Logger.matrixClient.error("auth error: token rejected (not soft logout); stopping sync")
            await syncService?.stop()
        }
    }
}

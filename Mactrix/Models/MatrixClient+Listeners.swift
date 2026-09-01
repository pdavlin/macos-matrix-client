import Foundation
import MatrixRustSDK
import OSLog

extension MatrixClient {
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

extension MatrixClient: SyncServiceStateObserver {
    nonisolated func onUpdate(state: MatrixRustSDK.SyncServiceState) {
        Task { @MainActor in
            syncState = state
        }
    }
}

extension MatrixClient: VerificationStateListener {
    nonisolated func onUpdate(status: MatrixRustSDK.VerificationState) {
        Task { @MainActor in
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
            // that a previously-verified identity no longer matches.
            await checkOwnIdentityViolation()
        }
    }

    /// Queries the SDK for the account's own identity violation state.
    ///
    /// Called when `verificationState` changes. The SDK's
    /// `UserIdentity.hasVerificationViolation()` reports `true` when the
    /// identity was previously verified but no longer is — the exact signal
    /// for an own-identity reset (e.g. from Element Web).
    private func checkOwnIdentityViolation() async {
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
}

extension MatrixClient: RecoveryStateListener {
    nonisolated func onUpdate(status: MatrixRustSDK.RecoveryState) {
        Task { @MainActor in
            recoveryState = status
        }
        let name = switch status {
        case .unknown: "unknown"
        case .enabled: "enabled"
        case .disabled: "disabled"
        case .incomplete: "incomplete"
        }
        Logger.matrixClient.info("recovery state: \(name, privacy: .public)")
    }
}

extension MatrixClient: RoomListServiceStateListener {
    nonisolated func onUpdate(state: MatrixRustSDK.RoomListServiceState) {
        Task { @MainActor in
            // Logged because this state gates the recovery UI (see
            // `RecoveryPrompt`) and because an empty sidebar is otherwise
            // indistinguishable from a room list that never started.
            let name = switch state {
            case .initial: "initial"
            case .settingUp: "settingUp"
            case .recovering: "recovering"
            case .running: "running"
            case .error: "error"
            case .terminated: "terminated"
            }
            Logger.matrixClient.info("room list state: \(name, privacy: .public) rooms=\(self.rooms.count, privacy: .public)")
            roomListServiceState = state
        }
    }
}

extension MatrixClient: RoomListServiceSyncIndicatorListener {
    nonisolated func onUpdate(syncIndicator: MatrixRustSDK.RoomListServiceSyncIndicator) {
        Task { @MainActor in
            showRoomSyncIndicator = syncIndicator
        }
    }
}

extension MatrixClient: MatrixRustSDK.ClientDelegate {
    nonisolated func onBackgroundTaskErrorReport(taskName: String, error: MatrixRustSDK.BackgroundTaskFailureReason) {
        // Both fields public: a task name and a failure reason are diagnostics,
        // not secrets, and the redacted version of this line was useless while
        // chasing an empty room list.
        Logger.matrixClient.error(
            "background task failed: \(taskName, privacy: .public) reason=\(String(describing: error), privacy: .public)"
        )
    }

    nonisolated func didReceiveAuthError(isSoftLogout: Bool) {
        Task { @MainActor in
            Logger.matrixClient.debug("did receive auth error: soft logout \(isSoftLogout, privacy: .public)")
            if !isSoftLogout {
                authenticationFailed = true
            }
        }
    }
}

extension MatrixClient: MatrixRustSDK.IgnoredUsersListener {
    nonisolated func call(ignoredUserIds: [String]) {
        Task { @MainActor in
            Logger.matrixClient.debug("Updated ignored users: \(ignoredUserIds)")
            self.ignoredUserIds = ignoredUserIds
        }
    }
}

extension MatrixClient: SessionVerificationControllerDelegate {
    nonisolated func didReceiveVerificationRequest(details: MatrixRustSDK.SessionVerificationRequestDetails) {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didReceiveVerificationRequest")
            sessionVerificationRequest = details
        }
    }

    nonisolated func didAcceptVerificationRequest() {
        Logger.matrixClient.debug("session verification: didAcceptVerificationRequest")
    }

    nonisolated func didStartSasVerification() {
        Logger.matrixClient.debug("session verification: didStartSasVerification")
    }

    nonisolated func didReceiveVerificationData(data: MatrixRustSDK.SessionVerificationData) {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didReceiveVerificationData")
            sessionVerificationData = data
        }
    }

    nonisolated func didFail() {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didFail")
            sessionVerificationRequest = nil
            sessionVerificationData = nil
        }
    }

    nonisolated func didCancel() {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didCancel")
            sessionVerificationRequest = nil
            sessionVerificationData = nil
        }
    }

    nonisolated func didFinish() {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didFinish")
            sessionVerificationRequest = nil
            sessionVerificationData = nil
        }
    }
}

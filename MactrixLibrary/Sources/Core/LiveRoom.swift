import Foundation
import MatrixRustSDK
import Models
import OSLog

@MainActor @Observable
public final class LiveRoom: Identifiable {
    public let sidebarRoom: SidebarRoom

    public var typingUserIds: [String] = []
    public var members: [MatrixRustSDK.RoomMember] = []

    /// What the signed-in account may redact in this room (MATRIX-110).
    ///
    /// Read from the power levels when the room opens, and again when the
    /// room info changes, because a power-level change arrives as a room info
    /// update. Rows read this stored value, so a hover never calls the SDK.
    /// It is `.none` until the first read finishes.
    public private(set) var redactPermission: Models.MessageRedactPermission = .none

    @ObservationIgnored private var typingHandle: TaskHandle?

    public var room: MatrixRustSDK.Room {
        sidebarRoom.room
    }

    public var roomInfo: MatrixRustSDK.RoomInfo? {
        sidebarRoom.roomInfo
    }

    public nonisolated var id: String {
        sidebarRoom.id
    }

    public init(sidebarRoom: SidebarRoom) {
        self.sidebarRoom = sidebarRoom

        startListening()
        observePowerLevels()

        Task(priority: .utility) {
            do {
                try await syncMembers()
            } catch {
                Logger.liveRoom.error("failed to sync room members: \(error)")
            }
        }
    }

    public convenience init(matrixRoom: MatrixRustSDK.Room) {
        self.init(sidebarRoom: SidebarRoom(room: matrixRoom))
    }

    isolated deinit {
        Logger.matrixClient.info("live room deinit")
    }

    fileprivate func startListening() {
        Logger.matrixClient.info("typing indicator start listening")

        let listener = AsyncSDKListener<[String]>()
        typingHandle = room.subscribeToTypingNotifications(listener: listener)

        Task { [weak self] in
            for await typingUserIds in listener {
                guard let self else { break }
                Logger.matrixClient.info("typing indicator updating UI")
                self.typingUserIds = typingUserIds
            }
        }
    }

    /// Reads the power levels now, and again on every room info change.
    ///
    /// The room info stream is debounced in `SidebarRoom`, and most updates
    /// change only unread counts, so the result is assigned only when it
    /// differs: rows do not re-render for an unrelated update.
    private func observePowerLevels() {
        withObservationTracking {
            _ = sidebarRoom.roomInfo
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observePowerLevels()
            }
        }
        Task { [weak self] in
            await self?.refreshRedactPermission()
        }
    }

    private func refreshRedactPermission() async {
        let permission: Models.MessageRedactPermission
        do {
            permission = try await Models.MessageRedactPermission(powerLevels: room.getPowerLevels())
        } catch {
            Logger.liveRoom.error("failed to read power levels for room \(self.id): \(error)")
            return
        }
        if permission != redactPermission {
            redactPermission = permission
        }
    }

    public func syncMembers() async throws {
        let id = self.id
        Logger.liveRoom.debug("syncing members for room: \(id)")

        // Get the locally cached members first
        let membersNoSyncIter = try await room.membersNoSync()
        if let result = membersNoSyncIter.nextChunk(chunkSize: membersNoSyncIter.len()) {
            members = result
            Logger.liveRoom.debug("loaded \(result.count) members locally for room \(id)")
        }

        // Fetch the latest members from the homeserver, this gets the latest member list.
        let memberIter = try await room.members()
        if let result = memberIter.nextChunk(chunkSize: memberIter.len()) {
            members = result
            Logger.liveRoom.debug("synced \(result.count) members for room \(id)")
        }
    }
}

extension LiveRoom: Hashable {
    public nonisolated static func == (lhs: LiveRoom, rhs: LiveRoom) -> Bool {
        lhs.id == rhs.id
    }

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension LiveRoom: @MainActor Models.Room {
    public var displayName: String? {
        room.displayName()
    }

    public var topic: String? {
        room.topic()
    }

    public var encryptionState: Models.EncryptionState {
        room.encryptionState().asModel
    }
}

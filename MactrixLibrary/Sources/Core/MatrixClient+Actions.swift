import Foundation
import MatrixRustSDK
import OSLog
import UI

public extension MatrixClient {
    struct MatrixClientUserProfileActions: UserProfileActions {
        public let userId: String
        public let matrixClient: MatrixClient
        public let windowState: WindowState

        public func sendMessage() async {
            do {
                // Shared with the New Chat screen, so DMs started here are
                // encrypted too (MATRIX-75).
                windowState.selectedRoomId = try await matrixClient.startDirectChat(userId: userId)
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

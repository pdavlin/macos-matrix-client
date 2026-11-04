import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import Models
import OSLog

@MainActor @Observable
public final class SidebarRoom: Identifiable {
    public let id: String
    public private(set) var room: MatrixRustSDK.Room
    public var roomInfo: MatrixRustSDK.RoomInfo?
    /// The room's latest event, mapped for the chat-list preview (MATRIX-67).
    /// Refreshed with every room info fetch, so it moves with the unread
    /// counts.
    public private(set) var latestEvent: Models.ChatListLatestEvent?

    @ObservationIgnored private var roomInfoHandle: TaskHandle?
    @ObservationIgnored private var listenerTask: Task<Void, Never>?

    public init(room: MatrixRustSDK.Room) {
        self.id = room.id()
        self.room = room

        Task {
            do {
                self.roomInfo = try await room.roomInfo()
            } catch {
                Logger.SidebarRoom.error("Failed to fetch initial room info: \(error)")
            }
            await refreshLatestEvent()

            listenToRoomInfo()
        }
    }

    /// Updates the underlying room reference without replacing this instance.
    /// Preserves object identity and loaded roomInfo while ensuring the room
    /// object stays current. Re-subscribes to room info updates on the new reference.
    public func updateRoom(_ newRoom: MatrixRustSDK.Room) {
        assert(id == newRoom.id())
        room = newRoom
        listenerTask?.cancel()
        roomInfoHandle = nil
        Task {
            do {
                roomInfo = try await room.roomInfo()
            } catch {
                Logger.SidebarRoom.error("Failed to fetch room info on update: \(error)")
            }
            await refreshLatestEvent()
            listenToRoomInfo()
        }
    }

    private func listenToRoomInfo() {
        let listener = AsyncSDKListener<MatrixRustSDK.RoomInfo>()
        roomInfoHandle = room.subscribeToRoomInfoUpdates(listener: listener)

        listenerTask = Task { [weak self] in
            for await roomInfo in listener.debounce(for: .milliseconds(500)) {
                guard let self, !Task.isCancelled else { break }
                self.roomInfo = roomInfo
                await self.refreshLatestEvent()
            }
        }
    }

    /// Re-reads the latest event. Assigns only on change, so an unrelated room
    /// info update does not invalidate the row.
    private func refreshLatestEvent() async {
        let event = await room.latestEvent().chatListEvent
        if event != latestEvent {
            latestEvent = event
        }
    }
}

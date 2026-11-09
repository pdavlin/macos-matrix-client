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
    /// The fetch started by `init` or the latest `updateRoom`. A newer
    /// `updateRoom` cancels it, so an older fetch cannot overwrite newer room
    /// info (MATRIX-130).
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init(room: MatrixRustSDK.Room) {
        self.id = room.id()
        self.room = room

        loadTask = Task { [weak self] in
            await self?.load(from: room)
        }
    }

    /// Updates the underlying room reference without replacing this instance.
    /// Preserves object identity and loaded roomInfo while ensuring the room
    /// object stays current. Re-subscribes to room info updates on the new reference.
    public func updateRoom(_ newRoom: MatrixRustSDK.Room) {
        assert(id == newRoom.id())
        room = newRoom
        loadTask?.cancel()
        listenerTask?.cancel()
        listenerTask = nil
        roomInfoHandle = nil
        loadTask = Task { [weak self] in
            await self?.load(from: newRoom)
        }
    }

    /// Fetches room info and the latest event for `room`, then subscribes to
    /// its room info updates.
    ///
    /// Takes the room as a parameter instead of reading `self.room`, so the
    /// task reads no observable state it does not need (MATRIX-130). Checks
    /// for cancellation after each suspension, so a fetch that a newer
    /// `updateRoom` replaced writes nothing.
    ///
    /// - Parameter room: the room reference this fetch belongs to.
    private func load(from room: MatrixRustSDK.Room) async {
        do {
            let info = try await room.roomInfo()
            guard !Task.isCancelled else { return }
            roomInfo = info
        } catch {
            Logger.SidebarRoom.error("Failed to fetch room info: \(error)")
        }
        guard !Task.isCancelled else { return }
        await refreshLatestEvent(from: room)
        guard !Task.isCancelled else { return }
        listenToRoomInfo(on: room)
    }

    private func listenToRoomInfo(on room: MatrixRustSDK.Room) {
        let listener = AsyncSDKListener<MatrixRustSDK.RoomInfo>()
        roomInfoHandle = room.subscribeToRoomInfoUpdates(listener: listener)

        listenerTask = Task { [weak self] in
            for await roomInfo in listener.debounce(for: .milliseconds(500)) {
                guard let self, !Task.isCancelled else { break }
                self.roomInfo = roomInfo
                await self.refreshLatestEvent(from: room)
            }
        }
    }

    /// Re-reads the latest event. Assigns only on change, so an unrelated room
    /// info update does not invalidate the row. A cancelled caller assigns
    /// nothing: its room reference is stale.
    ///
    /// - Parameter room: the room reference the caller belongs to.
    private func refreshLatestEvent(from room: MatrixRustSDK.Room) async {
        let event = await room.latestEvent().chatListEvent
        guard !Task.isCancelled else { return }
        if event != latestEvent {
            latestEvent = event
        }
    }
}

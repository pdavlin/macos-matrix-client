import Foundation
import MatrixRustSDK
import Models
import OSLog

/// Every chat the label sheet can offer (MATRIX-77).
///
/// The sidebar's room list holds only what the window's filter and label
/// selection allow, so the sheet opens a second, unfiltered view of the same
/// SDK room list (spaces left out) for as long as it is on screen. Rows are
/// built from the room's synchronous accessors only: no room info
/// subscription per row.
@MainActor @Observable
final class LabelChatDirectory {
    private(set) var chats: [ChatListRowModel] = []

    /// The sheet lists many more chats than the sidebar's first page.
    private static let pageSize: UInt32 = 1000

    @ObservationIgnored private var rooms: [MatrixRustSDK.Room] = []
    @ObservationIgnored private var handle: RoomListEntriesWithDynamicAdaptersResult?
    @ObservationIgnored private var task: Task<Void, Never>?

    func start(roomListService: RoomListService) async {
        guard handle == nil else { return }
        let listener = AsyncSDKListener<[RoomListEntriesUpdate]>()
        do {
            let handle = try await roomListService.allRooms().entriesWithDynamicAdapters(pageSize: Self.pageSize, listener: listener)
            if !handle.controller().setFilter(kind: .nonSpace) {
                Logger.labels.error("label chat directory: room list rejected the non-space filter")
            }
            self.handle = handle
        } catch {
            Logger.labels.error("label chat directory failed to start: \(String(describing: error), privacy: .public)")
            return
        }

        task = Task { [weak self] in
            for await updates in listener {
                guard let self, !Task.isCancelled else { break }
                self.apply(updates)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        handle?.entriesStream().cancel()
        handle = nil
    }

    private func apply(_ updates: [RoomListEntriesUpdate]) {
        for update in updates {
            switch update {
            case let .append(values): rooms.append(contentsOf: values)
            case .clear: rooms.removeAll()
            case let .pushFront(room): rooms.insert(room, at: 0)
            case let .pushBack(room): rooms.append(room)
            case .popFront: if !rooms.isEmpty { rooms.removeFirst() }
            case .popBack: if !rooms.isEmpty { rooms.removeLast() }
            case let .insert(index, room): rooms.insert(room, at: min(Int(index), rooms.count))
            case let .set(index, room): if rooms.indices.contains(Int(index)) { rooms[Int(index)] = room }
            case let .remove(index): if rooms.indices.contains(Int(index)) { rooms.remove(at: Int(index)) }
            case let .truncate(length): rooms.removeSubrange(min(Int(length), rooms.count) ..< rooms.count)
            case let .reset(values): rooms = values
            }
        }
        chats = rooms.map { room in
            ChatListRowModel(id: room.id(), title: room.displayName() ?? room.id(), avatarUrl: room.avatarUrl())
        }
    }
}

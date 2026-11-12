import Foundation
import MatrixRustSDK
import Models
import OSLog

/// Every room the ⌘K quick switcher can offer (MATRIX-114, D-7a).
///
/// The sidebar's `MatrixClient.rooms` holds only the first page of the
/// window's filter and label. A switcher that searched only that list would
/// miss a room whenever the sidebar shows Unread, People, or a label. So,
/// like `LabelChatDirectory` (MATRIX-77), this opens a second, unfiltered
/// view of the SDK room list (spaces left out) while the switcher is on
/// screen. It uses the same SDK calls as that class and adds none.
///
/// The SDK list is sorted by recent activity, so a room's index is its
/// recency rank. Names come from the room's synchronous accessor. The alias,
/// the DM flag, and the DM partner come from `RoomInfo`: the sidebar's copy
/// when the sidebar has the room, else one `roomInfo()` read per room.
@MainActor @Observable
public final class QuickSwitcherRoomDirectory {
    /// The rooms, most recent first.
    public private(set) var rooms: [QuickSwitcherRoom] = []

    /// Large enough for every room of one account.
    private static let pageSize: UInt32 = 1000

    @ObservationIgnored private var sdkRooms: [MatrixRustSDK.Room] = []
    @ObservationIgnored private var infos: [String: MatrixRustSDK.RoomInfo] = [:]
    @ObservationIgnored private var requestedInfoIds: Set<String> = []
    @ObservationIgnored private var handle: RoomListEntriesWithDynamicAdaptersResult?
    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var infoTask: Task<Void, Never>?

    public init() {}

    /// Shows the sidebar's rooms at once, before the full list arrives, and
    /// keeps their loaded room info so it is not read again.
    ///
    /// - Parameter sidebarRooms: `MatrixClient.rooms`, in SDK order.
    public func seed(sidebarRooms: [SidebarRoom]) {
        for sidebarRoom in sidebarRooms {
            if let roomInfo = sidebarRoom.roomInfo {
                infos[sidebarRoom.id] = roomInfo
            }
        }
        guard sdkRooms.isEmpty else { return }
        let chats = sidebarRooms.map(\.room).filter { !$0.isSpace() }
        rooms = chats.enumerated().map { rank, room in model(for: room, recencyRank: rank) }
    }

    /// Opens the unfiltered room list. Call `stop()` when the switcher closes.
    public func start(roomListService: RoomListService) async {
        guard handle == nil else { return }
        let listener = AsyncSDKListener<[RoomListEntriesUpdate]>()
        do {
            let handle = try await roomListService.allRooms().entriesWithDynamicAdapters(pageSize: Self.pageSize, listener: listener)
            if !handle.controller().setFilter(kind: .nonSpace) {
                Logger.matrixClient.error("quick switcher: room list rejected the non-space filter")
            }
            self.handle = handle
        } catch {
            Logger.matrixClient.error("quick switcher: room directory failed to start: \(String(describing: error), privacy: .public)")
            return
        }

        listTask = Task { [weak self] in
            for await updates in listener {
                guard let self, !Task.isCancelled else { break }
                self.apply(updates)
            }
        }
    }

    public func stop() {
        listTask?.cancel()
        listTask = nil
        infoTask?.cancel()
        infoTask = nil
        handle?.entriesStream().cancel()
        handle = nil
    }

    private func apply(_ updates: [RoomListEntriesUpdate]) {
        for update in updates {
            switch update {
            case let .append(values): sdkRooms.append(contentsOf: values)
            case .clear: sdkRooms.removeAll()
            case let .pushFront(room): sdkRooms.insert(room, at: 0)
            case let .pushBack(room): sdkRooms.append(room)
            case .popFront: if !sdkRooms.isEmpty { sdkRooms.removeFirst() }
            case .popBack: if !sdkRooms.isEmpty { sdkRooms.removeLast() }
            case let .insert(index, room): sdkRooms.insert(room, at: min(Int(index), sdkRooms.count))
            case let .set(index, room): if sdkRooms.indices.contains(Int(index)) { sdkRooms[Int(index)] = room }
            case let .remove(index): if sdkRooms.indices.contains(Int(index)) { sdkRooms.remove(at: Int(index)) }
            case let .truncate(length): sdkRooms.removeSubrange(min(Int(length), sdkRooms.count) ..< sdkRooms.count)
            case let .reset(values): sdkRooms = values
            }
        }
        rebuild()
        loadMissingInfos()
    }

    private func rebuild() {
        rooms = sdkRooms.enumerated().map { rank, room in model(for: room, recencyRank: rank) }
    }

    /// Reads the room info of rooms the sidebar did not have, then rebuilds
    /// once, so aliases and DM partners become searchable.
    private func loadMissingInfos() {
        let missing = sdkRooms.filter { room in
            let id = room.id()
            return infos[id] == nil && !requestedInfoIds.contains(id)
        }
        guard !missing.isEmpty else { return }
        requestedInfoIds.formUnion(missing.map { $0.id() })

        let previous = infoTask
        infoTask = Task { [weak self] in
            await previous?.value
            for room in missing {
                guard !Task.isCancelled else { return }
                do {
                    let roomInfo = try await room.roomInfo()
                    self?.infos[room.id()] = roomInfo
                } catch {
                    Logger.matrixClient.error("quick switcher: room info failed for \(room.id()): \(error)")
                }
            }
            self?.rebuild()
        }
    }

    private func model(for room: MatrixRustSDK.Room, recencyRank: Int) -> QuickSwitcherRoom {
        let id = room.id()
        let roomInfo = infos[id]
        let isDirect = roomInfo?.isDirect == true
        return QuickSwitcherRoom(
            id: id,
            name: room.displayName() ?? (isDirect ? "Unknown user" : "Unknown room"),
            canonicalAlias: roomInfo?.canonicalAlias,
            avatarUrl: room.avatarUrl(),
            isDirect: isDirect,
            // A DM's first hero is the other member (see
            // `MatrixClient.recentDirectContacts`).
            directUserId: isDirect ? roomInfo?.heroes.first?.userId : nil,
            recencyRank: recencyRank,
            network: roomInfo.flatMap { ChatListNetwork.detect(heroUserIds: $0.heroes.map(\.userId) + $0.serviceMembers) }
        )
    }
}

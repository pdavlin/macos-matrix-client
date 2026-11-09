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

    /// MATRIX-133: the members loaded for a group without a room avatar and
    /// with too few visible heroes. `chatListRow` takes the cluster faces,
    /// the "+N" count, and the network badge from it. Nil until a load ends.
    public private(set) var memberCluster: Models.ChatListMemberCluster?

    /// Where the member fallback stands for this room in this session.
    private enum MemberLoadState {
        /// No decision yet. The next row appearance starts one.
        case idle
        /// A decision task runs or waits for a load slot.
        case deciding
        /// The source is decided, or a load ended (with or without a
        /// result). Nothing loads again in this session.
        case decided
    }

    @ObservationIgnored private var memberLoadState = MemberLoadState.idle
    /// Chat-list rows and pinned tiles of this room on screen now. A queued
    /// member load starts only when this is above zero.
    @ObservationIgnored private var visibleRowCount = 0

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

    // MARK: - Member fallback (MATRIX-133)

    /// Call when a chat-list row or pinned tile of this room appears. The
    /// first call in the session decides where the bubble cluster gets its
    /// faces, and loads the room's members when the heroes do not suffice.
    public func chatListRowDidAppear() {
        visibleRowCount += 1
        guard memberLoadState == .idle else { return }
        memberLoadState = .deciding
        Task { [weak self] in
            await self?.decideClusterSource()
        }
    }

    /// Call when a chat-list row or pinned tile of this room disappears.
    public func chatListRowDidDisappear() {
        visibleRowCount = max(0, visibleRowCount - 1)
    }

    /// Decides the cluster source and, for a group without a room avatar and
    /// with fewer than two visible heroes, loads its members.
    ///
    /// Waits for the first room info fetch when it has not ended. The load
    /// waits for a slot in `ChatListMemberLoadGate.shared`. When the slot
    /// comes and no row of this room is on screen, the decision goes back to
    /// idle so the next appearance starts it again. A load runs at most once
    /// per session, also when it fails.
    private func decideClusterSource() async {
        if roomInfo == nil {
            await loadTask?.value
        }
        guard let info = roomInfo else {
            memberLoadState = .idle
            return
        }
        let currentRoom = room
        let avatarUrl = currentRoom.avatarUrl()
        let visibleHeroCount = info.chatListHeroes.count
        guard Models.ChatListMemberCluster.isClusterCandidate(isDirect: info.isDirect, avatarUrl: avatarUrl) else {
            memberLoadState = .decided
            return
        }
        guard Models.ChatListMemberCluster.needsMembers(
            isDirect: info.isDirect,
            avatarUrl: avatarUrl,
            visibleHeroCount: visibleHeroCount
        ) else {
            memberLoadState = .decided
            logClusterSource(.heroes, info: info, visibleHeroCount: visibleHeroCount, members: nil)
            return
        }

        let gate = ChatListMemberLoadGate.shared
        await gate.acquire()
        guard visibleRowCount > 0 else {
            await gate.release()
            memberLoadState = .idle
            return
        }
        let cluster = await loadMemberCluster(from: currentRoom, serviceMembers: info.serviceMembers)
        await gate.release()

        memberLoadState = .decided
        memberCluster = cluster
        let source = cluster.map { (loaded: Models.ChatListMemberCluster) -> Models.ChatListClusterSource in
            loaded.drawsCluster ? loaded.source : .none
        } ?? .none
        logClusterSource(source, info: info, visibleHeroCount: visibleHeroCount, members: cluster)
    }

    /// Loads the members from the local store, and from the homeserver when
    /// the store gives fewer than two other joined members.
    ///
    /// - Parameters:
    ///   - room: the room reference to load from.
    ///   - serviceMembers: the room's service members, which never get a face.
    /// - Returns: the cluster from the last load that worked, or nil when
    ///   both loads failed.
    private func loadMemberCluster(
        from room: MatrixRustSDK.Room,
        serviceMembers: [String]
    ) async -> Models.ChatListMemberCluster? {
        let ownUserId = room.ownUserId()
        var cluster: Models.ChatListMemberCluster?
        do {
            let members = try await room.membersNoSync().allChatListMembers()
            cluster = Models.ChatListMemberCluster(
                members: members,
                ownUserId: ownUserId,
                serviceMembers: serviceMembers,
                source: .localMembers
            )
        } catch {
            Logger.SidebarRoom.error("Failed to read local members of \(self.id, privacy: .public): \(error)")
        }
        if let cluster, cluster.otherMemberCount >= Models.ChatListAvatarChoice.clusterMinimumHeroes {
            return cluster
        }
        do {
            let members = try await room.members().allChatListMembers()
            cluster = Models.ChatListMemberCluster(
                members: members,
                ownUserId: ownUserId,
                serviceMembers: serviceMembers,
                source: .fetchedMembers
            )
        } catch {
            Logger.SidebarRoom.error("Failed to fetch members of \(self.id, privacy: .public): \(error)")
        }
        return cluster
    }

    /// The MATRIX-133 diagnostic line: one per group row without a room
    /// avatar, when its cluster source is decided. Room ID and counts only,
    /// never a name. Debug level; the app's Info.plist persists it, so
    /// `log show --debug` finds it.
    private func logClusterSource(
        _ source: Models.ChatListClusterSource,
        info: MatrixRustSDK.RoomInfo,
        visibleHeroCount: Int,
        members: Models.ChatListMemberCluster?
    ) {
        let heroCount = info.heroes.count
        let joinedCount = info.joinedMembersCount
        let memberCount = members.map { (cluster: Models.ChatListMemberCluster) -> String in
            String(cluster.otherMemberCount)
        } ?? "-"
        Logger.SidebarRoom.debug(
            """
            cluster source room=\(self.id, privacy: .public) \
            heroes=\(heroCount, privacy: .public) visibleHeroes=\(visibleHeroCount, privacy: .public) \
            joined=\(joinedCount, privacy: .public) otherMembers=\(memberCount, privacy: .public) \
            source=\(source.rawValue, privacy: .public)
            """
        )
    }
}

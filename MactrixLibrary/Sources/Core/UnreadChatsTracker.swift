import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The unread state of every non-space room of the account, for the Dock
/// badge (MATRIX-119).
///
/// The sidebar's `MatrixClient.rooms` holds only the first page of the
/// window's filter and label, so it cannot give an account-wide count. Like
/// `QuickSwitcherRoomDirectory` (MATRIX-114), this opens a second, unfiltered
/// view of the SDK room list with spaces left out. It lives for the whole
/// signed-in session: `DockBadgeController` starts it from
/// `MatrixClient.startSync()` and stops it from `MatrixClient.reset()`.
///
/// Each listed room gets one room-info subscription, the same call
/// `SidebarRoom` makes, because a change of the notification mode (mute) or
/// of the read state must reach the badge even when the room does not move in
/// the list. All subscriptions feed one stream, so the tracker runs one task,
/// not one task per room.
///
/// `chats` changes at most once per `publishDelay`: the first change after a
/// publish starts the timer, and every change before it fires joins the same
/// publish. A plain debounce would never fire while sync delivers a steady
/// stream of updates.
@MainActor @Observable
public final class UnreadChatsTracker {
    /// The unread inputs of every listed room, keyed by room ID.
    public private(set) var chats: [String: UnreadChatState] = [:]

    /// Large enough for every room of one account. Same value as
    /// `QuickSwitcherRoomDirectory.pageSize`.
    private static let pageSize: UInt32 = 1000

    /// How long changes collect before `chats` updates. Same value as the
    /// room-info debounce in `SidebarRoom`.
    private static let publishDelay: Duration = .milliseconds(500)

    /// The newest state of each room. Copied to `chats` on publish.
    @ObservationIgnored private var latest: [String: UnreadChatState] = [:]
    @ObservationIgnored private var sdkRooms: [MatrixRustSDK.Room] = []
    @ObservationIgnored private var infoHandles: [String: TaskHandle] = [:]
    @ObservationIgnored private var infoForwarder: RoomInfoForwarder?
    @ObservationIgnored private var handle: RoomListEntriesWithDynamicAdaptersResult?
    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var infoStreamTask: Task<Void, Never>?
    @ObservationIgnored private var initialReadTask: Task<Void, Never>?
    @ObservationIgnored private var publishTask: Task<Void, Never>?

    public init() {}

    /// Opens the unfiltered room list. Does nothing if the tracker already
    /// runs. A failure is logged and leaves the badge empty: the rest of the
    /// session does not depend on it.
    ///
    /// - Parameter roomListService: the room list service of the sync service
    ///   that `MatrixClient.startSync()` just built.
    public func start(roomListService: RoomListService) async {
        guard handle == nil else { return }

        let (infoStream, infoContinuation) = AsyncStream<MatrixRustSDK.RoomInfo>.makeStream()
        let listener = AsyncSDKListener<[RoomListEntriesUpdate]>()
        do {
            let handle = try await roomListService.allRooms().entriesWithDynamicAdapters(pageSize: Self.pageSize, listener: listener)
            if !handle.controller().setFilter(kind: .nonSpace) {
                Logger.matrixClient.error("unread chats: room list rejected the non-space filter")
            }
            self.handle = handle
        } catch {
            Logger.matrixClient.error("unread chats: room list failed to start: \(String(describing: error), privacy: .public)")
            infoContinuation.finish()
            return
        }
        infoForwarder = RoomInfoForwarder(continuation: infoContinuation)

        infoStreamTask = Task { [weak self] in
            for await roomInfo in infoStream {
                guard let self, !Task.isCancelled else { break }
                self.record(roomInfo)
            }
        }
        listTask = Task { [weak self] in
            for await updates in listener {
                guard let self, !Task.isCancelled else { break }
                self.apply(updates)
            }
        }
    }

    /// Closes the room list, drops every subscription, and empties `chats`
    /// at once, so the badge clears on sign-out without the publish delay.
    public func stop() {
        listTask?.cancel()
        listTask = nil
        infoStreamTask?.cancel()
        infoStreamTask = nil
        initialReadTask?.cancel()
        initialReadTask = nil
        publishTask?.cancel()
        publishTask = nil

        for infoHandle in infoHandles.values {
            infoHandle.cancel()
        }
        infoHandles.removeAll()
        infoForwarder?.finish()
        infoForwarder = nil
        handle?.entriesStream().cancel()
        handle = nil

        sdkRooms.removeAll()
        latest.removeAll()
        if !chats.isEmpty {
            chats = [:]
        }
    }

    // MARK: Room list

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
        syncSubscriptions()
    }

    /// Subscribes to rooms that joined the list and drops rooms that left it
    /// (a left room, or a room that became a space).
    private func syncSubscriptions() {
        var listed: [String: MatrixRustSDK.Room] = [:]
        for room in sdkRooms {
            listed[room.id()] = room
        }

        let removedIds = infoHandles.keys.filter { listed[$0] == nil }
        for roomId in removedIds {
            infoHandles.removeValue(forKey: roomId)?.cancel()
            latest.removeValue(forKey: roomId)
        }

        guard let infoForwarder else { return }
        let added = listed.filter { infoHandles[$0.key] == nil }.map(\.value)
        for room in added {
            infoHandles[room.id()] = room.subscribeToRoomInfoUpdates(listener: infoForwarder)
        }
        readInitialInfos(of: added)

        if !removedIds.isEmpty {
            schedulePublish()
        }
    }

    // MARK: Room info

    /// Reads the current room info of newly listed rooms. The subscription
    /// reports changes only, not the value at the time it starts. Reads run
    /// one at a time, after any earlier batch.
    private func readInitialInfos(of rooms: [MatrixRustSDK.Room]) {
        guard !rooms.isEmpty else { return }
        let previous = initialReadTask
        initialReadTask = Task { [weak self] in
            await previous?.value
            for room in rooms {
                guard !Task.isCancelled else { return }
                do {
                    let roomInfo = try await room.roomInfo()
                    self?.record(roomInfo)
                } catch {
                    Logger.matrixClient.error("unread chats: room info failed for \(room.id()): \(error)")
                }
            }
        }
    }

    /// Keeps the newest state of a listed room. A late value for a room that
    /// left the list is dropped.
    private func record(_ roomInfo: MatrixRustSDK.RoomInfo) {
        guard infoHandles[roomInfo.id] != nil else { return }
        let state = UnreadChatState(
            roomId: roomInfo.id,
            numUnreadNotifications: roomInfo.numUnreadNotifications,
            numUnreadMessages: roomInfo.numUnreadMessages,
            isDirect: roomInfo.isDirect,
            isMarkedUnread: roomInfo.isMarkedUnread,
            isMuted: roomInfo.isMuted
        )
        guard latest[roomInfo.id] != state else { return }
        latest[roomInfo.id] = state
        schedulePublish()
    }

    // MARK: Publishing

    private func schedulePublish() {
        guard publishTask == nil else { return }
        publishTask = Task { [weak self] in
            try? await Task.sleep(for: Self.publishDelay)
            guard !Task.isCancelled, let self else { return }
            self.publishTask = nil
            if self.chats != self.latest {
                self.chats = self.latest
            }
        }
    }
}

/// Forwards the room-info updates of every subscribed room into one stream.
///
/// `RoomInfo` carries its room ID, so one forwarder serves every room.
private final class RoomInfoForwarder: RoomInfoListener {
    private let continuation: AsyncStream<MatrixRustSDK.RoomInfo>.Continuation

    init(continuation: AsyncStream<MatrixRustSDK.RoomInfo>.Continuation) {
        self.continuation = continuation
    }

    func call(roomInfo: MatrixRustSDK.RoomInfo) {
        continuation.yield(roomInfo)
    }

    func finish() {
        continuation.finish()
    }
}

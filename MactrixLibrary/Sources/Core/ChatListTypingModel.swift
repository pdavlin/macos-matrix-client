import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The typing state of the chat-list rows on the screen (MATRIX-224).
///
/// Each row runs `watch(_:)` while it is on the screen. A room gets one SDK
/// typing subscription (`Room.subscribeToTypingNotifications(listener:)`)
/// while a row of it is on the screen, and at most `subscriptionLimit`
/// rooms hold one at a time (`ChatListTypingSlots`). The open chat keeps its
/// own subscription in `LiveRoom`.
///
/// Keyed by room ID, not held by `SidebarRoom`: the room list makes a new
/// `SidebarRoom` when a room moves, and the row on the screen stays.
///
/// Cost: one SDK event handler and one task per subscription, idle until a
/// typing notice for the room arrives. Each subscribe and cancel writes a
/// debug line with the time of the subscribe call and the active count
/// (category "matrix-client", text "chat list typing").
@MainActor @Observable
public final class ChatListTypingModel {
    /// The display names of the people who type, without the user, by room
    /// ID. Only rooms where someone types are in it.
    public private(set) var names: [String: [String]] = [:]

    /// The most typing subscriptions at one time. A sidebar shows about 15
    /// to 25 rows; the List also keeps some rows next to the screen alive.
    public static let subscriptionLimit = 40

    private struct Subscription {
        let handle: TaskHandle
        let task: Task<Void, Never>
    }

    @ObservationIgnored private var slots = ChatListTypingSlots(limit: ChatListTypingModel.subscriptionLimit)
    /// The SDK room of each room on the screen, for a room that waits for
    /// a slot.
    @ObservationIgnored private var rooms: [String: MatrixRustSDK.Room] = [:]
    @ObservationIgnored private var subscriptions: [String: Subscription] = [:]
    /// Resolved display names, by room ID and user ID.
    @ObservationIgnored private var displayNames: [String: String] = [:]

    public init() {}

    /// Holds a typing subscription for each room while the caller runs.
    /// Returns when the caller's task is cancelled, for example when the
    /// row's `.task` ends because the row left the screen.
    ///
    /// - Parameter rooms: the SDK rooms of one row: one room, or the
    ///   members of a merged chat.
    public func watch(_ rooms: [MatrixRustSDK.Room]) async {
        let roomIds = rooms.map { $0.id() }
        for room in rooms {
            self.rooms[room.id()] = room
        }
        apply(slots.appear(roomIds))
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        apply(slots.disappear(roomIds))
        for roomId in roomIds where !slots.isOnScreen(roomId) {
            self.rooms[roomId] = nil
        }
    }

    /// Cancels every subscription, for the sign-out.
    public func reset() {
        apply(slots.removeAll())
        rooms.removeAll()
        displayNames.removeAll()
        if !names.isEmpty {
            names = [:]
        }
    }

    private func apply(_ change: ChatListTypingSlots.Change) {
        for roomId in change.unsubscribe {
            if let subscription = subscriptions.removeValue(forKey: roomId) {
                subscription.handle.cancel()
                subscription.task.cancel()
            }
            if names[roomId] != nil {
                names[roomId] = nil
            }
            Logger.matrixClient.debug(
                "chat list typing: cancel room=\(roomId, privacy: .public) active=\(self.subscriptions.count, privacy: .public)"
            )
        }
        for roomId in change.subscribe {
            guard let room = rooms[roomId] else { continue }
            subscribe(room, roomId: roomId)
        }
    }

    private func subscribe(_ room: MatrixRustSDK.Room, roomId: String) {
        let start = ContinuousClock.now
        let listener = AsyncSDKListener<[String]>()
        let handle = room.subscribeToTypingNotifications(listener: listener)
        let elapsed = start.duration(to: .now)
        let ownUserId = room.ownUserId()
        let task = Task { [weak self] in
            for await userIds in listener {
                guard let self, !Task.isCancelled else { break }
                await self.update(roomId: roomId, room: room, userIds: userIds.filter { $0 != ownUserId })
            }
        }
        subscriptions[roomId] = Subscription(handle: handle, task: task)
        Logger.matrixClient.debug(
            """
            chat list typing: subscribe room=\(roomId, privacy: .public) \
            active=\(self.subscriptions.count, privacy: .public) \
            waiting=\(self.slots.waitingCount, privacy: .public) \
            took=\(elapsed.wholeMicroseconds, privacy: .public)us
            """
        )
    }

    private func update(roomId: String, room: MatrixRustSDK.Room, userIds: [String]) async {
        var resolved: [String] = []
        for userId in userIds {
            let name = await displayName(of: userId, in: room, roomId: roomId)
            resolved.append(name)
        }
        // The row can leave the screen while the names load.
        guard subscriptions[roomId] != nil else { return }
        let value: [String]? = resolved.isEmpty ? nil : resolved
        if names[roomId] != value {
            names[roomId] = value
        }
    }

    /// The member's display name in the room, read one time per room and
    /// user, or the user ID's localpart when the room has none.
    private func displayName(of userId: String, in room: MatrixRustSDK.Room, roomId: String) async -> String {
        let key = roomId + " " + userId
        if let cached = displayNames[key] {
            return cached
        }
        var name = ChatListSender.localpart(of: userId)
        do {
            if let displayName = try await room.memberDisplayName(userId: userId), !displayName.isEmpty {
                name = displayName
            }
        } catch {
            Logger.matrixClient.error("chat list typing: no display name for a member of \(roomId, privacy: .public): \(error)")
        }
        displayNames[key] = name
        return name
    }
}

extension Duration {
    /// The duration in whole microseconds, for the cost log lines.
    var wholeMicroseconds: Int64 {
        components.seconds * 1_000_000 + components.attoseconds / 1_000_000_000_000
    }
}

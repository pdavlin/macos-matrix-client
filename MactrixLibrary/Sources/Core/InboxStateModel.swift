import Foundation
import MatrixRustSDK
import Models
import Observation
import OSLog

/// The account's inbox states (MATRIX-206 Archive, MATRIX-207 Snooze and
/// Remind me later), kept in global account data under
/// `InboxStateDocument.eventType`.
///
/// The same design as `MergedChatsModel` (MATRIX-140): the SDK has no change
/// listener for a custom account data type, so `MatrixClient` re-reads the
/// local store when sync starts, when the room list reaches `running`, and
/// when a window becomes active. Writes are read-modify-write, one at a
/// time, and `InboxStateEchoGate` covers the gap before the sync echo.
///
/// The model also applies the activity rule
/// (`InboxStateDocument.applyActivity(_:in:merges:)`): a message from
/// another person moves an archived chat back to the Inbox. It reads each
/// room's latest event through the SDK (`Room.latestEvent()`) when the
/// room's unread state changes in `UnreadChatsTracker`, and for every room
/// with a state after each re-read of the store.
@MainActor @Observable
public final class InboxStateModel {
    /// The inbox states to show. Empty until the first read, and when the
    /// stored event cannot be read.
    public private(set) var document = InboxStateDocument()

    /// False when the stored event could not be read or came from a newer
    /// schema: every write is refused.
    public private(set) var isEditable = true

    @ObservationIgnored private let client: ClientProtocol
    @ObservationIgnored private let mergedChats: @MainActor () -> MergedChatDocument
    @ObservationIgnored private var echoGate = InboxStateEchoGate()
    @ObservationIgnored private var writeQueue: Task<Void, Never>?

    /// The unread state of each room with an inbox state when the activity
    /// rule last looked at it.
    @ObservationIgnored private var seenStates: [String: UnreadChatState] = [:]
    @ObservationIgnored private weak var tracker: UnreadChatsTracker?
    @ObservationIgnored private var watchGeneration = 0

    // MATRIX-207: the timer for the next snooze end or reminder. Used by
    // `InboxStateModel+Due.swift`.
    @ObservationIgnored var dueTimer: Task<Void, Never>?
    @ObservationIgnored var dueGeneration = 0
    @ObservationIgnored var dueNotify: (@MainActor (_ title: String, _ body: String, _ roomId: String) -> Void)?
    @ObservationIgnored var wakeObserver: (any NSObjectProtocol)?

    /// - Parameters:
    ///   - client: the SDK client.
    ///   - mergedChats: the account's merged chats, so an action on one
    ///     member applies to the whole merged chat.
    init(client: ClientProtocol, mergedChats: @escaping @MainActor () -> MergedChatDocument) {
        self.client = client
        self.mergedChats = mergedChats
    }

    /// The SDK client, for the due-time actions.
    var sdkClient: ClientProtocol {
        client
    }

    /// The account's merged chats now.
    var merges: MergedChatDocument {
        mergedChats()
    }

    // MARK: Reading

    /// Re-reads the inbox states from the SDK's local store, then applies
    /// the activity rule to every room with a state.
    public func refresh() async {
        let result: InboxStateReadResult
        do {
            result = try await InboxStateDocument.read(client.accountData(eventType: InboxStateDocument.eventType))
        } catch {
            Logger.inbox.error("failed to read inbox states: \(String(describing: error), privacy: .public)")
            return
        }
        if let accepted = echoGate.accept(result) {
            adopt(accepted)
        } else {
            Logger.inbox.debug("inbox states read is older than the last write; keeping the written document")
        }
        await checkActivity(roomIds: Array(document.rooms.keys))
    }

    private func adopt(_ result: InboxStateReadResult) {
        if case let .unreadable(raw, reason) = result {
            Logger.inbox.error(
                "inbox states account data is unreadable; writes are off. reason=\(reason, privacy: .public) raw=\(raw, privacy: .private)"
            )
        } else if case let .parsed(stored) = result, !stored.isWritable {
            Logger.inbox.error("inbox states account data has version \(stored.version, privacy: .public); writes are off")
        }
        let document = result.document
        if document != self.document {
            self.document = document
        }
        let editable = result.writableBase != nil
        if editable != isEditable {
            isEditable = editable
        }
    }

    // MARK: Derived state

    /// The list `roomId` shows in. A merged chat is one chat.
    public func placement(of roomId: String) -> InboxPlacement {
        document.placement(of: roomId, merges: mergedChats())
    }

    /// The rooms that show in `placement` (empty for the Inbox).
    public func roomIds(in placement: InboxPlacement) -> Set<String> {
        document.roomIds(in: placement, merges: mergedChats())
    }

    /// The archived and snoozed rooms: the Inbox, the rail filters, and the
    /// badges leave them out.
    public var hiddenRoomIds: Set<String> {
        document.hiddenRoomIds(merges: mergedChats())
    }

    // MARK: Actions

    /// The states of `roomIds` and their merged-chat siblings now, for an
    /// undo (`restore(_:)`).
    public func states(of roomIds: some Sequence<String>) -> [String: InboxRoomState] {
        let ids = InboxStateDocument.chatRoomIds(for: roomIds, merges: mergedChats())
        return Dictionary(uniqueKeysWithValues: ids.map { ($0, document.state(of: $0)) })
    }

    /// Archives the chats of `roomIds`. A room in a merged chat archives
    /// the whole merged chat.
    ///
    /// - Returns: the queued write.
    @discardableResult
    public func archive(roomIds: [String]) async -> Task<Void, Never> {
        let ids = InboxStateDocument.chatRoomIds(for: roomIds, merges: mergedChats())
        let time = await actionTime(roomIds: ids)
        return mutate { $0.archive(ids, at: time) }
    }

    /// Moves the chats of `roomIds` back to the Inbox.
    @discardableResult
    public func unarchive(roomIds: [String]) -> Task<Void, Never> {
        let ids = InboxStateDocument.chatRoomIds(for: roomIds, merges: mergedChats())
        return mutate { $0.unarchive(ids) }
    }

    /// Snoozes the chats of `roomIds` until `until` (MATRIX-207). An
    /// archived chat leaves the Archived list.
    @discardableResult
    public func snooze(roomIds: [String], until: Date) async -> Task<Void, Never> {
        let ids = InboxStateDocument.chatRoomIds(for: roomIds, merges: mergedChats())
        let time = await actionTime(roomIds: ids)
        return mutate { $0.snooze(ids, until: until, at: time) }
    }

    /// Ends the snooze of the chats of `roomIds` now.
    @discardableResult
    public func unsnooze(roomIds: [String]) -> Task<Void, Never> {
        let ids = InboxStateDocument.chatRoomIds(for: roomIds, merges: mergedChats())
        return mutate { $0.unsnooze(ids) }
    }

    /// Sets a reminder on the chats of `roomIds` for `remindAt` (MATRIX-207).
    @discardableResult
    public func remind(roomIds: [String], at remindAt: Date) async -> Task<Void, Never> {
        let ids = InboxStateDocument.chatRoomIds(for: roomIds, merges: mergedChats())
        let time = await actionTime(roomIds: ids)
        return mutate { $0.remind(ids, at: remindAt, setAt: time) }
    }

    /// Drops the reminder of the chats of `roomIds`.
    @discardableResult
    public func cancelReminder(roomIds: [String]) -> Task<Void, Never> {
        let ids = InboxStateDocument.chatRoomIds(for: roomIds, merges: mergedChats())
        return mutate { $0.cancelReminder(ids) }
    }

    /// The snooze end of the chat that holds `roomId`, if it is snoozed.
    public func snoozedUntil(of roomId: String) -> Date? {
        document.snoozedUntil(of: roomId, merges: mergedChats())
    }

    /// The ⌘K mark of the chat that holds `roomId`: "Archived", "Snoozed
    /// until …", or nil in the Inbox (`InboxStateDocument.searchMark`).
    public func searchMark(of roomId: String, now: Date = .now) -> String? {
        document.searchMark(of: roomId, merges: mergedChats(), now: now)
    }

    /// The reminder time of the chat that holds `roomId`, if it has one.
    public func remindAt(of roomId: String) -> Date? {
        document.remindAt(of: roomId, merges: mergedChats())
    }

    /// Puts back the states an action replaced (the Undo of a toast).
    @discardableResult
    public func restore(_ states: [String: InboxRoomState]) -> Task<Void, Never> {
        mutate { document in
            for (roomId, state) in states {
                document.set(state, for: roomId)
            }
        }
    }

    /// The time an action on `roomIds` stores: now, or just after the
    /// newest latest event of the rooms
    /// (`InboxStateDocument.actionTime(now:latestActivity:)`).
    func actionTime(roomIds: [String]) async -> Date {
        var newest: Date?
        for roomId in roomIds {
            guard let activity = await activity(of: roomId) else { continue }
            newest = max(newest ?? activity.timestamp, activity.timestamp)
        }
        return InboxStateDocument.actionTime(now: .now, latestActivity: newest)
    }

    // MARK: Activity rule

    /// Watches the tracker's unread states. When a room with an inbox state
    /// changes, its latest event is read and the activity rule applied.
    public func startWatching(_ tracker: UnreadChatsTracker) {
        self.tracker = tracker
        seenStates = [:]
        watch()
    }

    private func watch() {
        guard let tracker else { return }
        watchGeneration += 1
        let generation = watchGeneration
        let (chats, watched) = withObservationTracking {
            (tracker.chats, Set(document.rooms.keys))
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.watchGeneration else { return }
                self.watch()
            }
        }
        var changed: [String] = []
        for roomId in watched {
            guard let state = chats[roomId], state != seenStates[roomId] else { continue }
            seenStates[roomId] = state
            changed.append(roomId)
        }
        seenStates = seenStates.filter { watched.contains($0.key) }
        guard !changed.isEmpty else { return }
        Task { [weak self] in
            await self?.checkActivity(roomIds: changed)
        }
    }

    /// Reads the latest event of each room with a state and applies the
    /// activity rule. Writes only when a rule fires.
    public func checkActivity(roomIds: [String]) async {
        let merges = mergedChats()
        var preview = document
        var found: [(roomId: String, activity: InboxActivity)] = []
        for roomId in roomIds where preview.rooms[roomId] != nil {
            guard let activity = await activity(of: roomId) else { continue }
            if preview.applyActivity(activity, in: roomId, merges: merges) {
                found.append((roomId, activity))
            }
        }
        guard !found.isEmpty else { return }
        Logger.inbox.info("activity changed the inbox state of \(found.count, privacy: .public) chat(s)")
        await mutate { document in
            for (roomId, activity) in found {
                document.applyActivity(activity, in: roomId, merges: merges)
            }
        }.value
    }

    /// The latest event of `roomId`, or nil when the client does not know
    /// the room or the room has none.
    func activity(of roomId: String) async -> InboxActivity? {
        let room: MatrixRustSDK.Room?
        do {
            room = try client.getRoom(roomId: roomId)
        } catch {
            Logger.inbox.error("failed to get room \(roomId, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
        return await room?.latestEvent().inboxActivity
    }

    // MARK: Writing

    /// Applies `change` to the newest inbox states and writes the result.
    /// Changes run in order, one at a time. A change that leaves the
    /// document as it was writes nothing. The write is refused when the
    /// stored event is unreadable or newer than this build.
    @discardableResult
    public func mutate(_ change: @escaping (inout InboxStateDocument) -> Void) -> Task<Void, Never> {
        let previous = writeQueue
        let task = Task { [weak self] in
            await previous?.value
            await self?.write(change)
        }
        writeQueue = task
        return task
    }

    private func write(_ change: (inout InboxStateDocument) -> Void) async {
        let base: InboxStateDocument
        if let pending = echoGate.pendingDocument() {
            base = pending
        } else {
            let read: InboxStateReadResult
            do {
                read = try await InboxStateDocument.read(client.accountData(eventType: InboxStateDocument.eventType))
            } catch {
                Logger.inbox.error("failed to read inbox states before a write: \(String(describing: error), privacy: .public)")
                return
            }
            guard let writable = read.writableBase else {
                adopt(read)
                Logger.inbox.error("refusing to write inbox states: the stored document cannot be written by this build")
                return
            }
            base = writable
        }

        var updated = base
        change(&updated)
        guard updated != base else {
            adopt(.parsed(base))
            return
        }

        do {
            try await client.setAccountData(eventType: InboxStateDocument.eventType, content: updated.jsonString())
            echoGate.didWrite(updated)
            adopt(.parsed(updated))
        } catch {
            Logger.inbox.error("failed to write inbox states: \(String(describing: error), privacy: .public)")
        }
    }
}

extension MatrixRustSDK.LatestEventValue {
    /// The latest event as the inbox rules read it. A local echo is the
    /// account's own event; an invite comes from another person.
    var inboxActivity: InboxActivity? {
        switch self {
        case .none:
            nil
        case let .remote(timestamp: timestamp, sender: _, isOwn: isOwn, profile: _, content: _):
            InboxActivity(timestamp: Self.date(timestamp), isOwn: isOwn)
        case let .remoteInvite(timestamp: timestamp, inviter: _, inviterProfile: _):
            InboxActivity(timestamp: Self.date(timestamp), isOwn: false)
        case let .local(timestamp: timestamp, sender: _, profile: _, content: _, state: _):
            InboxActivity(timestamp: Self.date(timestamp), isOwn: true)
        }
    }
}

import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The account's chat labels (MATRIX-77), kept in global account data under
/// `ChatLabelDocument.eventType`.
///
/// The SDK has no change listener for a custom account data type
/// (`observeAccountDataEvent` takes only the built-in types), so the model
/// re-reads the local store when sync starts running, when a window becomes
/// active, and after each of its own writes. Writes are read-modify-write and
/// run one at a time; `ChatLabelEchoGate` covers the gap between a write and
/// its sync echo, when the store still holds the old document.
@MainActor @Observable
final class LabelsModel {
    /// The labels to show. Empty until the first read, and when the stored
    /// event cannot be read.
    private(set) var document = ChatLabelDocument()

    /// False when the stored event could not be read or came from a newer
    /// schema: every write is refused so that data this build does not
    /// understand is not overwritten.
    private(set) var isEditable = true

    /// One live room per labelled room, so the rail badges follow unread
    /// counts whatever the chat list's filter holds.
    private(set) var trackedRooms: [String: SidebarRoom] = [:]

    @ObservationIgnored private let client: ClientProtocol
    @ObservationIgnored private let notifications: MatrixNotifications
    @ObservationIgnored private var echoGate = ChatLabelEchoGate()
    @ObservationIgnored private var writeQueue: Task<Void, Never>?

    init(client: ClientProtocol, notifications: MatrixNotifications) {
        self.client = client
        self.notifications = notifications
    }

    // MARK: Reading

    /// Re-reads the labels from the SDK's local store.
    func refresh() async {
        let result: ChatLabelReadResult
        do {
            result = try await ChatLabelDocument.read(client.accountData(eventType: ChatLabelDocument.eventType))
        } catch {
            Logger.labels.error("failed to read labels: \(String(describing: error), privacy: .public)")
            return
        }
        guard let accepted = echoGate.accept(result) else {
            Logger.labels.debug("labels read is older than the last write; keeping the written labels")
            return
        }
        adopt(accepted)
    }

    private func adopt(_ result: ChatLabelReadResult) {
        if case let .unreadable(raw, reason) = result {
            Logger.labels.error(
                "labels account data is unreadable; writes are off. reason=\(reason, privacy: .public) raw=\(raw, privacy: .private)"
            )
        } else if case let .parsed(document) = result, !document.isWritable {
            Logger.labels.error("labels account data has version \(document.version, privacy: .public); writes are off")
        }

        let document = result.document
        if document != self.document {
            self.document = document
        }
        let editable = result.writableBase != nil
        if editable != isEditable {
            isEditable = editable
        }
        notifications.labelMutedRoomIds = document.labelMutedRoomIds
        updateTrackedRooms()
    }

    /// Starts tracking newly labelled rooms and drops rooms no label holds.
    /// A room the SDK does not know yet is retried on the next read.
    private func updateTrackedRooms() {
        let wanted = document.labelledRoomIds
        var tracked = trackedRooms.filter { wanted.contains($0.key) }
        for roomId in wanted where tracked[roomId] == nil {
            do {
                if let room = try client.getRoom(roomId: roomId) {
                    tracked[roomId] = SidebarRoom(room: room)
                }
            } catch {
                Logger.labels.error("failed to look up labelled room: \(String(describing: error), privacy: .public)")
            }
        }
        if Set(tracked.keys) != Set(trackedRooms.keys) {
            trackedRooms = tracked
        }
    }

    // MARK: Derived state

    /// The rail badge of every label, from the tracked rooms' unread counts.
    var badges: [String: ChatLabelBadge] {
        var unread: [String: ChatListUnread] = [:]
        for (roomId, room) in trackedRooms {
            guard let info = room.roomInfo else { continue }
            unread[roomId] = ChatListUnread(
                numUnreadMessages: info.numUnreadMessages,
                numUnreadNotifications: info.numUnreadNotifications,
                numUnreadMentions: info.numUnreadMentions,
                isMarkedUnread: info.isMarkedUnread,
                isMuted: info.isMuted
            )
        }
        return Dictionary(uniqueKeysWithValues: document.labels.map { ($0.id, ChatLabelBadge.badge(for: $0, unread: unread)) })
    }

    // MARK: Writing

    /// Applies `change` to the current labels and writes the result. Changes
    /// run in order, one at a time, each on the newest document, so a change
    /// should name labels by ID and state the value it wants (add, not
    /// toggle) to stay correct when another device wrote in between.
    func mutate(_ change: @escaping (inout ChatLabelDocument) -> Void) {
        let previous = writeQueue
        writeQueue = Task { [weak self] in
            await previous?.value
            await self?.write(change)
        }
    }

    private func write(_ change: (inout ChatLabelDocument) -> Void) async {
        let base: ChatLabelDocument
        if let pending = echoGate.pendingDocument() {
            // The store has not caught up with the last write yet.
            base = pending
        } else {
            let read: ChatLabelReadResult
            do {
                read = try await ChatLabelDocument.read(client.accountData(eventType: ChatLabelDocument.eventType))
            } catch {
                Logger.labels.error("failed to read labels before a write: \(String(describing: error), privacy: .public)")
                return
            }
            guard let writable = read.writableBase else {
                adopt(read)
                Logger.labels.error("refusing to write labels: the stored labels cannot be read by this build")
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
            try await client.setAccountData(eventType: ChatLabelDocument.eventType, content: updated.jsonString())
            echoGate.didWrite(updated)
            adopt(.parsed(updated))
        } catch {
            Logger.labels.error("failed to write labels: \(String(describing: error), privacy: .public)")
        }
    }
}

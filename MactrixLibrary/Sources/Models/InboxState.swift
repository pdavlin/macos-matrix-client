import Foundation

/// The inbox state of one room (MATRIX-206 Archive, MATRIX-207 Snooze and
/// Remind me later). Times only: the account data that holds it is not
/// encrypted on the server, so it never holds message text.
///
/// Archive and snooze exclude each other: each action clears the other. A
/// reminder is independent of both.
public struct InboxRoomState: Equatable, Sendable {
    /// When the room was archived. Nil when it is not archived.
    public var archivedAt: Date?
    /// When the snooze ends. Nil when the room is not snoozed.
    public var snoozedUntil: Date?
    /// When the snooze was set. A message from another person after this
    /// time ends the snooze early.
    public var snoozedAt: Date?
    /// When the reminder comes due. Nil when there is no reminder.
    public var remindAt: Date?
    /// When the reminder was set. A message from another person after this
    /// time drops the reminder.
    public var remindSetAt: Date?

    public init(
        archivedAt: Date? = nil,
        snoozedUntil: Date? = nil,
        snoozedAt: Date? = nil,
        remindAt: Date? = nil,
        remindSetAt: Date? = nil
    ) {
        self.archivedAt = archivedAt
        self.snoozedUntil = snoozedUntil
        self.snoozedAt = snoozedAt
        self.remindAt = remindAt
        self.remindSetAt = remindSetAt
    }

    /// No field is set: the room has no inbox state.
    public var isEmpty: Bool {
        archivedAt == nil && snoozedUntil == nil && snoozedAt == nil && remindAt == nil && remindSetAt == nil
    }

    /// Milliseconds since the Unix epoch, the unit of the wire format.
    static func milliseconds(of date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// Every time rounded to whole milliseconds, so a state equals itself
    /// after a round trip through the wire format (the echo gate compares
    /// the written document with the read one).
    var roundedToMilliseconds: InboxRoomState {
        func round(_ date: Date?) -> Date? {
            date.map { Date(timeIntervalSince1970: TimeInterval(Self.milliseconds(of: $0)) / 1000) }
        }
        return InboxRoomState(
            archivedAt: round(archivedAt),
            snoozedUntil: round(snoozedUntil),
            snoozedAt: round(snoozedAt),
            remindAt: round(remindAt),
            remindSetAt: round(remindSetAt)
        )
    }

    /// The list the room shows in.
    public var placement: InboxPlacement {
        if snoozedUntil != nil {
            return .snoozed
        }
        if archivedAt != nil {
            return .archived
        }
        return .inbox
    }
}

/// The list a chat shows in (MATRIX-206, MATRIX-207).
public enum InboxPlacement: String, Sendable, CaseIterable {
    /// The Inbox and every other list filter and rail filter.
    case inbox
    /// The Archived list filter only.
    case archived
    /// The Snoozed list filter only.
    case snoozed
}

/// The account's inbox states, by room ID (MATRIX-206, MATRIX-207).
///
/// Stored in global account data under `eventType` (contract §11,
/// 2026-11-19):
///
///     {"version": 1, "rooms": {"!a:davlin.io": {"archived_at": 1763500000000},
///       "!b:davlin.io": {"snoozed_until": 1763560000000, "snoozed_at": 1763500000000,
///       "remind_at": 1763540000000, "remind_set_at": 1763500000000}}}
///
/// Times are milliseconds since the Unix epoch. A merged chat (MATRIX-139)
/// has one entry per member room, and every action writes all members, so
/// the merged chat acts as one chat. Fields this build does not know are
/// kept through a read-modify-write.
public struct InboxStateDocument: Equatable, Sendable {
    /// The global account-data event type.
    public static let eventType = "io.davlin.matrixclient.inbox_state"

    /// The schema version this build writes.
    public static let currentVersion = 1

    public var version: Int
    /// The rooms with a state. Never holds an empty state.
    public private(set) var rooms: [String: InboxRoomState]
    /// Top-level fields this build does not know, written back unchanged.
    var unknownFields: [String: JSONValue]
    /// Fields of each room entry this build does not know, by room ID. Never
    /// holds an empty dictionary or a room that `rooms` lacks.
    var roomUnknownFields: [String: [String: JSONValue]]

    public init(version: Int = InboxStateDocument.currentVersion, rooms: [String: InboxRoomState] = [:]) {
        self.version = version
        self.rooms = rooms.filter { !$0.value.isEmpty }.mapValues(\.roundedToMilliseconds)
        unknownFields = [:]
        roomUnknownFields = [:]
    }

    init(
        version: Int,
        rooms: [String: InboxRoomState],
        unknownFields: [String: JSONValue],
        roomUnknownFields: [String: [String: JSONValue]]
    ) {
        self.version = version
        self.rooms = rooms.filter { !$0.value.isEmpty }
        self.unknownFields = unknownFields
        self.roomUnknownFields = roomUnknownFields
        prune()
    }

    /// This build may write the document. A newer schema is read but never
    /// overwritten.
    public var isWritable: Bool {
        version <= Self.currentVersion
    }

    /// The state of `roomId`, empty when it has none.
    public func state(of roomId: String) -> InboxRoomState {
        rooms[roomId] ?? InboxRoomState()
    }

    /// The list `roomId` shows in, by its own state alone. The chat list
    /// uses `placement(of:merges:)`, which treats a merged chat as one.
    public func placement(of roomId: String) -> InboxPlacement {
        state(of: roomId).placement
    }

    /// The list `roomId` shows in, with a merged chat as one chat: when any
    /// member is in the Inbox, every member is; else when any member is
    /// snoozed, every member is. Members disagree only when a room joined a
    /// merged chat after the action, or another client wrote one member.
    public func placement(of roomId: String, merges: MergedChatDocument) -> InboxPlacement {
        guard let merge = merges.merge(containing: roomId) else {
            return placement(of: roomId)
        }
        let placements = Set(merge.rooms.map(placement(of:)))
        if placements.contains(.inbox) {
            return .inbox
        }
        if placements.contains(.snoozed) {
            return .snoozed
        }
        return .archived
    }

    /// The rooms with a state that shows them in `placement`, merged chats
    /// counted as one (`placement(of:merges:)`). For `.inbox` this is empty:
    /// a room with no state is in the Inbox and has no entry.
    public func roomIds(in placement: InboxPlacement, merges: MergedChatDocument) -> Set<String> {
        guard placement != .inbox else { return [] }
        var result = Set<String>()
        for roomId in rooms.keys where self.placement(of: roomId, merges: merges) == placement {
            if let merge = merges.merge(containing: roomId) {
                result.formUnion(merge.rooms)
            } else {
                result.insert(roomId)
            }
        }
        return result
    }

    /// The rooms that leave the Inbox, every other list filter, every rail
    /// filter, and the badges: the archived and the snoozed rooms.
    public func hiddenRoomIds(merges: MergedChatDocument) -> Set<String> {
        roomIds(in: .archived, merges: merges).union(roomIds(in: .snoozed, merges: merges))
    }

    // MARK: Mutations

    /// Sets the state of `roomId`. An empty state removes the entry.
    public mutating func set(_ state: InboxRoomState, for roomId: String) {
        if state.isEmpty {
            rooms.removeValue(forKey: roomId)
            roomUnknownFields.removeValue(forKey: roomId)
        } else {
            rooms[roomId] = state.roundedToMilliseconds
        }
    }

    /// Changes the state of each room in `roomIds`.
    public mutating func update(_ roomIds: some Sequence<String>, _ change: (inout InboxRoomState) -> Void) {
        for roomId in roomIds {
            var state = state(of: roomId)
            change(&state)
            set(state, for: roomId)
        }
    }

    /// Archives the rooms at `time`. A snooze ends; a reminder stays.
    public mutating func archive(_ roomIds: some Sequence<String>, at time: Date) {
        update(roomIds) { state in
            state.archivedAt = time
            state.snoozedUntil = nil
            state.snoozedAt = nil
        }
    }

    /// Moves the rooms back to the Inbox from the Archived list.
    public mutating func unarchive(_ roomIds: some Sequence<String>) {
        update(roomIds) { $0.archivedAt = nil }
    }

    private mutating func prune() {
        roomUnknownFields = roomUnknownFields.filter { rooms[$0.key] != nil && !$0.value.isEmpty }
    }
}

public extension InboxStateDocument {
    /// Every room an action on `roomIds` writes: each room, and every member
    /// of a merged chat that holds one of them, so a merged chat acts as
    /// one chat. In first-seen order, without repeats.
    static func chatRoomIds(for roomIds: some Sequence<String>, merges: MergedChatDocument) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for roomId in roomIds {
            let members = merges.merge(containing: roomId)?.rooms ?? [roomId]
            for member in members where seen.insert(member).inserted {
                result.append(member)
            }
        }
        return result
    }
}

/// A room's latest event, as the inbox rules read it (MATRIX-206).
public struct InboxActivity: Equatable, Sendable {
    /// The event's server timestamp.
    public var timestamp: Date
    /// The account sent it, from this device or any other.
    public var isOwn: Bool

    public init(timestamp: Date, isOwn: Bool) {
        self.timestamp = timestamp
        self.isOwn = isOwn
    }
}

public extension InboxStateDocument {
    /// The time an action (archive, snooze, reminder) stores: `now`, or one
    /// millisecond after the chat's latest event when that is later.
    ///
    /// The rules compare the action time with a server timestamp. A sender
    /// whose server clock runs ahead of this Mac would otherwise make the
    /// message the user just archived count as new, and undo the archive at
    /// once.
    static func actionTime(now: Date, latestActivity: Date?) -> Date {
        guard let latestActivity, latestActivity >= now else { return now }
        return latestActivity.addingTimeInterval(0.001)
    }

    /// Applies a room's latest event to the inbox state (MATRIX-206,
    /// MATRIX-207). A message from another person that is newer than an
    /// action ends it:
    /// - an archived chat goes back to the Inbox,
    /// - a snooze ends early,
    /// - a reminder is dropped (a reply came, so it does not fire).
    ///
    /// An own message, from any device, changes nothing. The change applies
    /// to every member of a merged chat that holds `roomId`.
    ///
    /// - Returns: true when the document changed.
    @discardableResult
    mutating func applyActivity(_ activity: InboxActivity, in roomId: String, merges: MergedChatDocument) -> Bool {
        guard !activity.isOwn, rooms[roomId] != nil else { return false }
        let state = state(of: roomId)
        let isNewer = { (time: Date?) in time.map { activity.timestamp > $0 } ?? false }
        let endsArchive = isNewer(state.archivedAt)
        let endsSnooze = state.snoozedUntil != nil && isNewer(state.snoozedAt)
        let dropsReminder = state.remindAt != nil && isNewer(state.remindSetAt)
        guard endsArchive || endsSnooze || dropsReminder else { return false }

        update(Self.chatRoomIds(for: [roomId], merges: merges)) { member in
            if endsArchive {
                member.archivedAt = nil
            }
            if endsSnooze {
                member.snoozedUntil = nil
                member.snoozedAt = nil
            }
            if dropsReminder {
                member.remindAt = nil
                member.remindSetAt = nil
            }
        }
        return true
    }
}

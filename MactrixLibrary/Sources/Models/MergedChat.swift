import Foundation

/// One merged chat (M2.5, MATRIX-139): several one-to-one chats with the same
/// person, shown as one chat-list row and one timeline.
///
/// This file holds the shared types only. It is added verbatim by every
/// M2.5 Phase A branch, so do not edit it on a story branch: the JSON codec
/// lives in `MergedChatDocument+Codec.swift` (MATRIX-140) and other logic in
/// each story's own files. Ask the orchestrator for a change here.
///
/// Stored in global account data under `MergedChatDocument.eventType`
/// (contract §11, 2026-11-10):
///
///     {"version": 1, "merges": [{"id": "…", "name": "Seth",
///       "rooms": ["!a:davlin.io", "!b:davlin.io"],
///       "default_room": "!a:davlin.io", "avatar_room": "!b:davlin.io"}]}
public struct MergedChat: Hashable, Sendable, Identifiable {
    /// A stable local identifier (a UUID string), not a room ID.
    public var id: String
    /// The name the merged chat shows.
    public var name: String
    /// The member room IDs, two or more, in the order the user added them.
    /// A room belongs to at most one merged chat.
    public var rooms: [String]
    /// The room a new message goes to after a long silence (send-target
    /// rule, contract §4 M2.5). Nil means the first member room.
    public var defaultRoom: String?
    /// The member room whose avatar the merged chat shows. Nil means the
    /// first member room with an avatar.
    public var avatarRoom: String?

    public init(id: String, name: String, rooms: [String], defaultRoom: String? = nil, avatarRoom: String? = nil) {
        self.id = id
        self.name = name
        self.rooms = rooms
        self.defaultRoom = defaultRoom
        self.avatarRoom = avatarRoom
    }

    /// The default room if it is still a member, else the first member.
    public var effectiveDefaultRoom: String? {
        if let defaultRoom, rooms.contains(defaultRoom) {
            return defaultRoom
        }
        return rooms.first
    }
}

/// The account's merged chats (MATRIX-139).
public struct MergedChatDocument: Equatable, Sendable {
    /// The global account-data event type (contract §11, 2026-11-10).
    public static let eventType = "io.davlin.matrixclient.merged_chats"

    /// The schema version this build writes.
    public static let currentVersion = 1

    public var version: Int
    public var merges: [MergedChat]

    public init(version: Int = MergedChatDocument.currentVersion, merges: [MergedChat] = []) {
        self.version = version
        self.merges = merges
    }

    /// This build may write the document. A newer schema is read but never
    /// overwritten.
    public var isWritable: Bool {
        version <= Self.currentVersion
    }

    /// The merged chat with this identifier.
    public func merge(id: String) -> MergedChat? {
        merges.first { $0.id == id }
    }

    /// The merged chat that holds `roomId`, if any.
    public func merge(containing roomId: String) -> MergedChat? {
        merges.first { $0.rooms.contains(roomId) }
    }

    /// Every room that belongs to a merged chat.
    public var mergedRoomIds: Set<String> {
        Set(merges.flatMap(\.rooms))
    }
}

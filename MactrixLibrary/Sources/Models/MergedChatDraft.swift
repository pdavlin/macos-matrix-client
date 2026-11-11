import Foundation

/// The editable state of the Merge Chats sheet (MATRIX-141).
///
/// The sheet's host owns the draft through a binding, so the "Add Chat…"
/// flow (the quick switcher, Phase B) can append a room while the sheet is
/// open. `mergedChat(id:)` turns a valid draft into the document value.
public struct MergedChatDraft: Equatable, Sendable {
    /// Fewest member chats a merged chat needs.
    public static let minimumMembers = 2

    /// The name field's text, untrimmed.
    public var name: String
    /// The member room IDs, in the order the user added them, no repeats.
    public var rooms: [String]
    /// The chosen default room. Nil, or a room that left the draft, means the
    /// first member (`effectiveDefaultRoom`).
    public var defaultRoom: String?
    /// The chosen avatar room. Nil, or a room that left the draft, means the
    /// first member with an avatar.
    public var avatarRoom: String?

    public init(name: String = "", rooms: [String] = [], defaultRoom: String? = nil, avatarRoom: String? = nil) {
        self.name = name
        self.rooms = []
        self.defaultRoom = defaultRoom
        self.avatarRoom = avatarRoom
        for roomId in rooms {
            add(roomId)
        }
    }

    /// The draft for editing an existing merged chat.
    public init(merge: MergedChat) {
        self.init(name: merge.name, rooms: merge.rooms, defaultRoom: merge.defaultRoom, avatarRoom: merge.avatarRoom)
    }

    /// The draft for a new merged chat from the chats the user picked, with
    /// the name prefilled from the first chat's title.
    ///
    /// - Parameter chats: the picked chats, in pick order.
    ///
    /// ```swift
    /// MergedChatDraft(chats: [sethSlack, sethWork]).name // "Seth Redacted"
    /// ```
    public init(chats: [ChatListRowModel]) {
        self.init(name: chats.first?.title ?? "", rooms: chats.map(\.id))
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Merge (or Save) is allowed: a non-blank name and at least
    /// `minimumMembers` chats.
    public var canSubmit: Bool {
        !trimmedName.isEmpty && rooms.count >= Self.minimumMembers
    }

    /// The default room if it is still a member, else the first member.
    public var effectiveDefaultRoom: String? {
        if let defaultRoom, rooms.contains(defaultRoom) {
            return defaultRoom
        }
        return rooms.first
    }

    /// Adds a chat at the end. A chat already in the draft stays where it is.
    public mutating func add(_ roomId: String) {
        guard !rooms.contains(roomId) else { return }
        rooms.append(roomId)
    }

    /// Removes a chat. A default or avatar choice that pointed at it goes
    /// back to automatic.
    public mutating func remove(_ roomId: String) {
        rooms.removeAll { $0 == roomId }
        if defaultRoom == roomId {
            defaultRoom = nil
        }
        if avatarRoom == roomId {
            avatarRoom = nil
        }
    }

    /// The avatar member the merged chat shows, by the same rule as the chat
    /// list (`ChatListMerging`): the chosen member, else the first member
    /// with an avatar image, else the first member.
    ///
    /// - Parameter hasAvatar: whether a member room has an avatar image.
    public func effectiveAvatarRoom(hasAvatar: (String) -> Bool) -> String? {
        if let avatarRoom, rooms.contains(avatarRoom) {
            return avatarRoom
        }
        return rooms.first(where: hasAvatar) ?? rooms.first
    }

    /// The document value for this draft: the trimmed name, and the default
    /// and avatar choices only when they still name a member.
    ///
    /// - Parameter id: the merged chat's ID: a new UUID string for a new
    ///   merged chat, the existing ID when editing.
    public func mergedChat(id: String) -> MergedChat {
        MergedChat(
            id: id,
            name: trimmedName,
            rooms: rooms,
            defaultRoom: defaultRoom.flatMap { rooms.contains($0) ? $0 : nil },
            avatarRoom: avatarRoom.flatMap { rooms.contains($0) ? $0 : nil }
        )
    }

    /// The label of each member chat in the sheet's pickers: the title and,
    /// when known, the network ("Seth · Slack"). Two members with the same
    /// label (two Slack workspaces) get " (2)", " (3)" after the second and
    /// later ones, so each picker entry names one chat.
    ///
    /// - Parameter chats: the member rows, in draft order.
    /// - Returns: one label per row, in the same order.
    public static func memberLabels(for chats: [ChatListRowModel]) -> [String] {
        var seen: [String: Int] = [:]
        return chats.map { chat in
            let base = chat.network.map { "\(chat.title) · \($0.displayName)" } ?? chat.title
            let count = seen[base, default: 0] + 1
            seen[base] = count
            return count == 1 ? base : "\(base) (\(count))"
        }
    }
}

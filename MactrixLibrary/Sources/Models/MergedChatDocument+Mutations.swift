import Foundation

// MATRIX-140: the mutating API of the merged-chats document.
//
// Invariants every mutation keeps (and `normalize()` restores):
// - a merge has two or more distinct rooms;
// - a room belongs to at most one merge;
// - `defaultRoom` and `avatarRoom` are nil or a member of their merge.
//
// Every mutation names its merge by ID, not by index: the app applies it to a
// freshly read document, where another window or device may have changed the
// merges since the user clicked. Each returns true when the request was
// valid and is now reflected in the document (already true counts), and
// false when it was refused: an unknown merge ID, a room that is not a
// member, or too few rooms. A refused request leaves the document unchanged.

public extension MergedChatDocument {
    /// The fewest rooms a merged chat may have.
    static let minimumRoomCount = 2

    /// Adds a merged chat at the end of the list and returns its ID.
    ///
    /// A room that is already in another merge moves to the new one, and a
    /// merge left with fewer than two rooms is removed.
    ///
    /// - Parameters:
    ///   - name: The name the merged chat shows.
    ///   - rooms: The member room IDs. Repeats are dropped.
    ///   - defaultRoom: Nil, or one of `rooms`.
    ///   - avatarRoom: Nil, or one of `rooms`.
    ///   - id: The new merge's ID. Pass your own to know it before the
    ///     write lands (`MergedChatsModel.mutate` returns nothing).
    /// - Returns: `id`, or nil when `rooms` has fewer than two distinct
    ///   rooms, `id` is taken, or a default or avatar room is not a member.
    @discardableResult
    mutating func create(
        name: String,
        rooms: [String],
        defaultRoom: String? = nil,
        avatarRoom: String? = nil,
        id: String = UUID().uuidString
    ) -> String? {
        let members = rooms.uniqued()
        guard members.count >= Self.minimumRoomCount,
              merge(id: id) == nil,
              Self.isNilOrMember(defaultRoom, of: members),
              Self.isNilOrMember(avatarRoom, of: members)
        else { return nil }
        detach(Set(members), except: nil)
        merges.append(MergedChat(id: id, name: name, rooms: members, defaultRoom: defaultRoom, avatarRoom: avatarRoom))
        return id
    }

    /// Renames a merged chat.
    @discardableResult
    mutating func rename(_ id: String, to name: String) -> Bool {
        update(id) { $0.name = name }
    }

    /// Replaces the member rooms of a merged chat, in the given order.
    ///
    /// Rooms in another merge move here, and a merge left with fewer than two
    /// rooms is removed. A default or avatar room that is no longer a member
    /// is cleared. Refused when fewer than two distinct rooms remain: use
    /// `unmerge(_:)` to dissolve a merge.
    @discardableResult
    mutating func setRooms(_ rooms: [String], for id: String) -> Bool {
        let members = rooms.uniqued()
        guard members.count >= Self.minimumRoomCount, merge(id: id) != nil else { return false }
        detach(Set(members), except: id)
        return update(id) { merge in
            merge.rooms = members
            merge.clearRoomsOutsideMembers()
        }
    }

    /// Adds a room at the end of a merged chat. A room in another merge
    /// moves here, and a merge left with fewer than two rooms is removed.
    @discardableResult
    mutating func addRoom(_ roomId: String, to id: String) -> Bool {
        guard let merge = merge(id: id) else { return false }
        if merge.rooms.contains(roomId) { return true }
        detach([roomId], except: id)
        return update(id) { $0.rooms.append(roomId) }
    }

    /// Removes a room from a merged chat. When one room would remain, the
    /// merge is removed. A default or avatar room equal to `roomId` is
    /// cleared.
    @discardableResult
    mutating func removeRoom(_ roomId: String, from id: String) -> Bool {
        guard let merge = merge(id: id), merge.rooms.contains(roomId) else { return false }
        if merge.rooms.count <= Self.minimumRoomCount {
            return unmerge(id)
        }
        return update(id) { merge in
            merge.rooms.removeAll { $0 == roomId }
            merge.clearRoomsOutsideMembers()
        }
    }

    /// Sets the room a new message goes to after a long silence. Nil means
    /// the first member room. Refused for a room that is not a member.
    @discardableResult
    mutating func setDefaultRoom(_ roomId: String?, for id: String) -> Bool {
        guard let merge = merge(id: id), Self.isNilOrMember(roomId, of: merge.rooms) else { return false }
        return update(id) { $0.defaultRoom = roomId }
    }

    /// Sets the member room whose avatar the merged chat shows. Nil means the
    /// first member room with an avatar. Refused for a room that is not a
    /// member.
    @discardableResult
    mutating func setAvatarRoom(_ roomId: String?, for id: String) -> Bool {
        guard let merge = merge(id: id), Self.isNilOrMember(roomId, of: merge.rooms) else { return false }
        return update(id) { $0.avatarRoom = roomId }
    }

    /// Removes a merged chat. Its rooms show as normal chats again.
    @discardableResult
    mutating func unmerge(_ id: String) -> Bool {
        guard merge(id: id) != nil else { return false }
        merges.removeAll { $0.id == id }
        return true
    }

    /// Drops every room ID not in `roomIds`, for rooms the account has left.
    /// A merge left with fewer than two rooms is removed.
    ///
    /// Pass the complete set of rooms the account is in. Calling this with a
    /// partial set (for example, before the room list has loaded) removes
    /// merges that are still valid.
    ///
    /// - Returns: True when the document changed.
    @discardableResult
    mutating func pruneRooms(keeping roomIds: Set<String>) -> Bool {
        let before = merges
        for index in merges.indices {
            merges[index].rooms.removeAll { !roomIds.contains($0) }
            merges[index].clearRoomsOutsideMembers()
        }
        merges.removeAll { $0.rooms.count < Self.minimumRoomCount }
        return merges != before
    }

    /// Restores the invariants after a change that may have broken them,
    /// such as content another client wrote: repeats in a merge are dropped,
    /// a room in several merges stays in the first one only, a default or
    /// avatar room that is not a member is cleared, and a merge with fewer
    /// than two rooms is removed. `MergedChatStoredDocument.update(_:)`
    /// calls this after every change.
    mutating func normalize() {
        var claimed = Set<String>()
        for index in merges.indices {
            merges[index].rooms = merges[index].rooms.uniqued().filter { !claimed.contains($0) }
            claimed.formUnion(merges[index].rooms)
            merges[index].clearRoomsOutsideMembers()
        }
        merges.removeAll { $0.rooms.count < Self.minimumRoomCount }
    }

    // MARK: Helpers

    private static func isNilOrMember(_ roomId: String?, of rooms: [String]) -> Bool {
        roomId.map { rooms.contains($0) } ?? true
    }

    /// Removes `roomIds` from every merge but `keptId`, then removes merges
    /// left with fewer than two rooms.
    private mutating func detach(_ roomIds: Set<String>, except keptId: String?) {
        for index in merges.indices where merges[index].id != keptId {
            merges[index].rooms.removeAll { roomIds.contains($0) }
            merges[index].clearRoomsOutsideMembers()
        }
        merges.removeAll { $0.id != keptId && $0.rooms.count < Self.minimumRoomCount }
    }

    private mutating func update(_ id: String, _ change: (inout MergedChat) -> Void) -> Bool {
        guard let index = merges.firstIndex(where: { $0.id == id }) else { return false }
        change(&merges[index])
        return true
    }
}

private extension MergedChat {
    /// Clears a default or avatar room that is not a member.
    mutating func clearRoomsOutsideMembers() {
        if let defaultRoom, !rooms.contains(defaultRoom) {
            self.defaultRoom = nil
        }
        if let avatarRoom, !rooms.contains(avatarRoom) {
            self.avatarRoom = nil
        }
    }
}

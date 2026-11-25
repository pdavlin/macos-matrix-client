import Foundation

/// The quick reactions of a room (MATRIX-262): the hover row's reaction
/// buttons and the React submenus.
///
/// `MessageActionModel.quickReactionCount` keys, no key twice, in this order:
/// 1. The room's own keys, the most used first. A tie goes to the most
///    recent use (`RoomReactionUsage.ranked`).
/// 2. The keys used in the rooms that share a space or a label with the
///    room, the most recent use first. The spaces are the rail's: a space
///    holds a room directly or through sub-spaces (`RoomSpaceMap`). A room in
///    more than one space or label takes the union of them all.
/// 3. The account's recent emoji (MATRIX-111).
/// 4. `MessageActionModel.defaultQuickReactionKeys`.
///
/// A custom emoji (an `mxc://` key) works only in the chats of its
/// workspace. So it comes in step 1, and in step 2 only from a room with a
/// direct parent space in common: the space whose image pack holds it
/// (MATRIX-155). A label can hold chats of other workspaces, and the recent
/// list is the account's, so neither gives a custom emoji (contract §11,
/// 2026-11-13 decision c, as amended 2026-11-25).
public enum QuickReactionRanking {
    /// The quick reactions of `roomId`.
    ///
    /// - Parameters:
    ///   - roomId: The room that holds the message.
    ///   - usage: The account's reaction use by room.
    ///   - spaces: The room-to-space map of the rail.
    ///   - labels: The account's labels.
    ///   - recents: The account's recent emoji, most recent first.
    /// - Returns: `MessageActionModel.quickReactionCount` distinct keys.
    public static func keys(
        forRoom roomId: String,
        usage: ReactionUsageDocument,
        spaces: RoomSpaceMap,
        labels: ChatLabelDocument,
        recents: [String]
    ) -> [String] {
        let count = MessageActionModel.quickReactionCount
        var keys = Array((usage.rooms[roomId]?.ranked ?? []).prefix(count))
        if keys.count < count {
            keys += nearbyKeys(of: roomId, usage: usage, spaces: spaces, labels: labels)
        }
        keys += recents.filter(RecentEmojiList.isRecordable)
        return MessageActionModel.quickReactionKeys(fromRecents: keys)
    }

    /// Step 2: the keys of the rooms that share a space or a label with
    /// `roomId`, the most recent use first. A tie goes to the key.
    static func nearbyKeys(
        of roomId: String,
        usage: ReactionUsageDocument,
        spaces: RoomSpaceMap,
        labels: ChatLabelDocument
    ) -> [String] {
        let roomSpaces = spaces.spaceIds(of: roomId)
        let roomParents = Set(spaces.parents[roomId] ?? [])
        let labelRooms = Set(labels.labels.filter { $0.rooms.contains(roomId) }.flatMap(\.rooms))
        var lastUse: [String: Date] = [:]
        for (otherId, other) in usage.rooms where otherId != roomId {
            guard labelRooms.contains(otherId)
                || (!roomSpaces.isEmpty && !spaces.spaceIds(of: otherId).isDisjoint(with: roomSpaces))
            else { continue }
            let sharesWorkspace = !roomParents.isDisjoint(with: spaces.parents[otherId] ?? [])
            for (key, use) in other.reactions where sharesWorkspace || !ImagePack.isImageKey(key) {
                lastUse[key] = max(lastUse[key] ?? use.lastUsedAt, use.lastUsedAt)
            }
        }
        return lastUse
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
    }
}

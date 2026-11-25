import Foundation

/// The chat search of the iOS chat list (MATRIX-247).
///
/// It is the ⌘K quick switcher's room search (MATRIX-114): the same rooms
/// (Core's `QuickSwitcherRoomDirectory`, every joined room, not only the
/// list's first page), the same fuzzy score, and the same order. It lists
/// rooms only: the phone has no New Chat, so the people rows of ⌘K do not
/// show.
///
/// MATRIX-248: a merged chat is one result, as it is one row of the chat
/// list. A member room that matches shows as its merged chat, and the
/// merged chat's name matches too. Archived and snoozed chats carry the ⌘K
/// mark (`InboxStateDocument.searchMark(of:merges:now:)`).
public enum ChatListSearch {
    /// The chats that match `query`, best first.
    ///
    /// - Parameters:
    ///   - rooms: every room the search can offer, in any order.
    ///   - query: the typed text.
    ///   - merges: the account's merged chats. A merged chat's result is
    ///     `mergedResult(merge:members:)`, at the place of its best match:
    ///     a member room or the merged chat's name.
    ///   - inbox: the account's inbox states, for the archived and snoozed
    ///     marks in `detail`.
    ///   - now: decides the words of a snooze end.
    ///   - limit: the most results to return.
    /// - Returns: nil for a blank query, so the chat list shows, as in other
    ///   iOS lists. Else `QuickSwitcherRanking.rankRooms`: the matching
    ///   chats by score, ties broken by recency. Empty when no chat matches.
    public static func results(
        in rooms: [QuickSwitcherRoom],
        query: String,
        merges: MergedChatDocument = MergedChatDocument(),
        inbox: InboxStateDocument = InboxStateDocument(),
        now: Date = .now,
        limit: Int = QuickSwitcherRanking.defaultRoomLimit
    ) -> [QuickSwitcherRoom]? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let chats = MergedSearchChats(rooms: rooms, merges: merges)
        let ranked = QuickSwitcherRanking.rankRooms(
            rooms + chats.nameCandidates,
            query: query,
            currentRoomId: nil,
            limit: .max
        )
        var shown = Set<String>()
        var results: [QuickSwitcherRoom] = []
        for candidate in ranked where results.count < limit {
            var result = chats.result(for: candidate)
            guard shown.insert(result.id).inserted else { continue }
            if let mark = inbox.searchMark(of: result.id, merges: merges, now: now) {
                result.detail = mark
            }
            results.append(result)
        }
        return results
    }

    /// The room that a tap on `room` opens: the ⌘K step for a room row
    /// (`QuickSwitcherRanking.decide`, Return).
    ///
    /// MATRIX-248: a merged chat's result is its newest member room
    /// (`mergedResult(merge:members:)`), so a tap opens that room with the
    /// normal single-room timeline. iOS has no merged timeline.
    public static func roomToOpen(_ room: QuickSwitcherRoom) -> String {
        guard case let .openRoom(roomId) = QuickSwitcherRanking.decide(.room(room), mode: .navigate, key: .primary) else {
            return room.id
        }
        return roomId
    }

    /// The search result of one merged chat (MATRIX-248): its newest member
    /// room, with the merged chat's name and avatar.
    ///
    /// - The newest member is the member first in the SDK's recency order
    ///   (the lowest `recencyRank`). The directory has no event times, and
    ///   the SDK sorts its list by the latest activity, so this is the
    ///   member with the newest message.
    /// - The name and the avatar follow the chat list's merged row
    ///   (`ChatListMerging`): the merged chat's name, else the avatar
    ///   member's name; the `avatarRoom` member's avatar, else the first
    ///   member's with an image, else the first member's.
    ///
    /// - Parameters:
    ///   - merge: the merged chat.
    ///   - members: the member rooms the search holds, in the merged chat's
    ///     order.
    /// - Returns: nil when no member is present.
    public static func mergedResult(merge: MergedChat, members: [QuickSwitcherRoom]) -> QuickSwitcherRoom? {
        guard let newest = members.min(by: { $0.recencyRank < $1.recencyRank }),
              let avatar = ChatListMerging.avatarMember(
                  merge: merge,
                  ordered: members,
                  roomId: \.id,
                  hasAvatarImage: { $0.avatarUrl != nil }
              )
        else {
            return nil
        }
        return QuickSwitcherRoom(
            id: newest.id,
            name: ChatListMerging.title(of: merge, avatarMemberTitle: avatar.name),
            avatarUrl: avatar.avatarUrl,
            isDirect: avatar.isDirect,
            recencyRank: newest.recencyRank
        )
    }
}

/// The merged chats among the search's rooms (MATRIX-248).
private struct MergedSearchChats {
    /// The ID of the merged chat that owns each member room, by room ID.
    private let mergeIdByRoom: [String: String]
    /// Each merged chat with a present member, by merged chat ID.
    private let resultByMerge: [String: QuickSwitcherRoom]
    /// One candidate per merged chat with a present member and a name, so
    /// the merged chat's name matches. Its ID is the merged chat's ID.
    let nameCandidates: [QuickSwitcherRoom]

    init(rooms: [QuickSwitcherRoom], merges: MergedChatDocument) {
        guard !merges.merges.isEmpty else {
            mergeIdByRoom = [:]
            resultByMerge = [:]
            nameCandidates = []
            return
        }
        let roomsById = Dictionary(rooms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let owners = ChatListMerging.mergeOwners(merges)
        var mergeIdByRoom: [String: String] = [:]
        var resultByMerge: [String: QuickSwitcherRoom] = [:]
        var nameCandidates: [QuickSwitcherRoom] = []
        for (index, merge) in merges.merges.enumerated() {
            var members: [QuickSwitcherRoom] = []
            for roomId in merge.rooms where owners[roomId] == index && !members.contains(where: { $0.id == roomId }) {
                if let room = roomsById[roomId] {
                    members.append(room)
                }
            }
            guard let result = ChatListSearch.mergedResult(merge: merge, members: members) else { continue }
            for member in members {
                mergeIdByRoom[member.id] = merge.id
            }
            resultByMerge[merge.id] = result
            let name = merge.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                nameCandidates.append(QuickSwitcherRoom(id: merge.id, name: name, recencyRank: result.recencyRank))
            }
        }
        self.mergeIdByRoom = mergeIdByRoom
        self.resultByMerge = resultByMerge
        self.nameCandidates = nameCandidates
    }

    /// The result for a ranked candidate: its merged chat's result, or the
    /// room itself.
    func result(for candidate: QuickSwitcherRoom) -> QuickSwitcherRoom {
        if let merged = resultByMerge[candidate.id] {
            return merged
        }
        if let mergeId = mergeIdByRoom[candidate.id], let merged = resultByMerge[mergeId] {
            return merged
        }
        return candidate
    }
}

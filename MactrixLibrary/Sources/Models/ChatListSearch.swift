import Foundation

/// The chat search of the iOS chat list (MATRIX-247).
///
/// It is the ⌘K quick switcher's room search (MATRIX-114): the same rooms
/// (Core's `QuickSwitcherRoomDirectory`, every joined room, not only the
/// list's first page), the same fuzzy score, and the same order. It lists
/// rooms only: the phone has no New Chat, so the people rows of ⌘K do not
/// show.
public enum ChatListSearch {
    /// The rooms that match `query`, best first.
    ///
    /// - Parameters:
    ///   - rooms: every room the search can offer, in any order.
    ///   - query: the typed text.
    ///   - limit: the most rooms to return.
    /// - Returns: nil for a blank query, so the chat list shows, as in other
    ///   iOS lists. Else `QuickSwitcherRanking.rankRooms`: the matching
    ///   rooms by score, ties broken by recency. Empty when no room matches.
    public static func results(
        in rooms: [QuickSwitcherRoom],
        query: String,
        limit: Int = QuickSwitcherRanking.defaultRoomLimit
    ) -> [QuickSwitcherRoom]? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return QuickSwitcherRanking.rankRooms(rooms, query: query, currentRoomId: nil, limit: limit)
    }

    /// The room that a tap on `room` opens: the ⌘K step for a room row
    /// (`QuickSwitcherRanking.decide`, Return).
    ///
    /// A member room of a merged chat opens itself. The Mac then shows the
    /// merged timeline; iOS has none (MATRIX-248), and its chat list shows a
    /// member room as a row of its own.
    public static func roomToOpen(_ room: QuickSwitcherRoom) -> String {
        guard case let .openRoom(roomId) = QuickSwitcherRanking.decide(.room(room), mode: .navigate, key: .primary) else {
            return room.id
        }
        return roomId
    }
}

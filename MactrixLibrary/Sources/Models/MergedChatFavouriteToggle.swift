import Foundation

/// The Favorite or Unfavorite item of a merged row's menu (MATRIX-189).
///
/// A merged chat is pinned when any member is a favourite
/// (`MergedChatListEntry.isFavourite`). Favorite sets the favourite tag on
/// every member room; Unfavorite clears it on every member room, so the
/// merged chat leaves the pinned grid. Like Mute (decision 2026-11-10), the
/// action is for the merged chat, so it names every member in the document,
/// also the ones the window's filter hides.
public struct MergedChatFavouriteToggle: Equatable, Sendable {
    /// The favourite value the action sets on each room.
    public var isFavourite: Bool
    /// The rooms the action changes: every member of the merged chat.
    public var roomIds: [String]

    /// The toggle for a merged row.
    ///
    /// - Parameter merged: the merged chat as the chat list shows it.
    public init(merged: MergedChatListEntry) {
        isFavourite = !merged.isFavourite
        roomIds = merged.merge.rooms
    }

    /// The menu item's title, the same as the room menu's.
    public var title: String {
        isFavourite ? "Favorite" : "Unfavorite"
    }

    /// The menu item's SF Symbol, the same as the room menu's.
    public var systemImage: String {
        isFavourite ? "heart" : "heart.slash"
    }
}

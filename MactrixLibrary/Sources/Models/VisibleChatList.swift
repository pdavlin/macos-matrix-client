import Foundation

/// The rooms the sidebar shows, in the order it shows them (MATRIX-115).
///
/// The sidebar draws `favorites` as the pinned grid and `list` as the chat
/// list below it. The Go menu walks `ordered` for ⌘1…⌘9 and ⇧⌘] / ⇧⌘[
/// (D-7b, D-7c). Both build this value with ``visible(rooms:labels:selectedLabelId:isFavourite:)``,
/// so the shortcuts can never disagree with what the sidebar shows.
public struct VisibleChatList<Room: Identifiable> where Room.ID == String {
    /// The pinned favourites grid, in grid order.
    public let favorites: [Room]
    /// The chat list below the grid. Favourites are not in it.
    public let list: [Room]

    public init(favorites: [Room], list: [Room]) {
        self.favorites = favorites
        self.list = list
    }

    /// The favourites grid, then the chat list: the order the sidebar
    /// shows and the Go menu walks.
    public var ordered: [Room] {
        favorites + list
    }

    /// Splits the client's rooms into what the sidebar shows.
    ///
    /// The chat-list filter and the selected label's room set are applied by
    /// the SDK before `rooms` arrive here (`setChatListFilter`). This applies
    /// the two rules the SDK cannot:
    /// - With no label selected (the Inbox), rooms of labels hidden from the
    ///   Inbox are dropped (MATRIX-77). A selected label shows all its rooms.
    /// - Favourites go to the pinned grid and every other room to the list.
    ///
    /// Both parts keep the SDK order, which is recency.
    ///
    /// - Parameters:
    ///   - rooms: The client's rooms in SDK order, without spaces.
    ///   - labels: The labels document.
    ///   - selectedLabelId: The window's selected label. An ID the labels do
    ///     not hold counts as no label, as in the sidebar.
    ///   - isFavourite: Whether a room is a favourite.
    public static func visible(
        rooms: [Room],
        labels: ChatLabelDocument,
        selectedLabelId: String?,
        isFavourite: (Room) -> Bool
    ) -> VisibleChatList {
        let selectedLabel = selectedLabelId.flatMap(labels.label(id:))
        let hidden = selectedLabel == nil ? labels.inboxHiddenRoomIds : []
        let shown = rooms.filter { !hidden.contains($0.id) }
        return VisibleChatList(
            favorites: shown.filter(isFavourite),
            list: shown.filter { !isFavourite($0) }
        )
    }
}

/// The Go menu's room navigation over a ``VisibleChatList`` order
/// (MATRIX-115, D-7b and D-7c).
public enum ChatListNavigation {
    /// ⌘1…⌘9.
    public static let shortcutCount = 9

    /// The rooms ⌘1…⌘9 open: element `n` is ⌘(n+1).
    ///
    /// With F favourites, ⌘1…⌘F are the favourites and the next keys are
    /// the first list rows, because `ordered` puts the grid first. Fewer
    /// rooms than keys gives a shorter array; the extra keys open nothing.
    public static func shortcutTargets<Room>(in ordered: [Room]) -> [Room] {
        Array(ordered.prefix(shortcutCount))
    }

    /// The room ⇧⌘] opens: the one after the selected room.
    ///
    /// With no room selected, or a selected room the sidebar does not show,
    /// this is the first room. At the last room it is `nil`: the walk stops
    /// and does not wrap.
    public static func next(after selectedRoomId: String?, in orderedIds: [String]) -> String? {
        guard let selectedRoomId, let index = orderedIds.firstIndex(of: selectedRoomId) else {
            return orderedIds.first
        }
        let nextIndex = orderedIds.index(after: index)
        return nextIndex < orderedIds.endIndex ? orderedIds[nextIndex] : nil
    }

    /// The room ⇧⌘[ opens: the one before the selected room.
    ///
    /// At the first room it is `nil`: the walk stops and does not wrap. With
    /// no room selected, or a selected room the sidebar does not show, it is
    /// also `nil`, because there is no place to step back from.
    public static func previous(before selectedRoomId: String?, in orderedIds: [String]) -> String? {
        guard let selectedRoomId, let index = orderedIds.firstIndex(of: selectedRoomId), index > orderedIds.startIndex else {
            return nil
        }
        return orderedIds[orderedIds.index(before: index)]
    }
}

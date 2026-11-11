import Core
import Models

/// The chats one window's sidebar shows (MATRIX-141 Phase B): the pinned grid
/// and the list, with merged chats folded in, and the `SidebarRoom` behind
/// each row for the per-room work (context menus, member loads).
///
/// Built by `SidebarView.visibleChatList(client:windowState:now:)`.
@MainActor
struct SidebarChatList {
    /// The grid and the list. `ordered` is what the Go menu walks.
    let visible: VisibleChatList<ChatListItem>
    /// The sidebar's rooms by room ID.
    private let roomsById: [String: SidebarRoom]

    /// - Parameters:
    ///   - visible: the merged and split chat list.
    ///   - rooms: the sidebar's chat rooms, the source of `visible`.
    init(visible: VisibleChatList<ChatListItem>, rooms: [SidebarRoom]) {
        self.visible = visible
        self.roomsById = Dictionary(rooms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The room behind a plain row, or the present members of a merged row,
    /// in the merged chat's order.
    func rooms(of item: ChatListItem) -> [SidebarRoom] {
        item.roomIds.compactMap { roomsById[$0] }
    }
}

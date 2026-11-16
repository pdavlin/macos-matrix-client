import Core
import MatrixRustSDK
import Models
import SwiftUI
import UI

// MATRIX-167: the app-side glue for spaces on the sidebar rail. The filter
// rules are in `Models/ChatListRailFilter.swift`; these functions feed them
// from the client.

/// What the rail and the chat list read from the client for the space filter.
@MainActor
enum SidebarRail {
    /// The account's chat rooms: every non-space room the Dock badge's
    /// unfiltered room list holds, plus the sidebar's rooms. The sidebar's
    /// own rooms are not enough: the selected filter narrows them.
    ///
    /// MATRIX-170: plus the chats of the launch cache until the SDK's space
    /// graph is ready, because the live lists are empty in the first frames.
    static func chatIds(client: MatrixClient) -> Set<String> {
        var ids = Set(client.dockBadge.unreadChats.chats.keys)
        ids.formUnion(client.roomAccounts.launchChatIds)
        for room in client.rooms where !room.room.isSpace() {
            ids.insert(room.id)
        }
        return ids
    }

    /// The top-level joined spaces, in the SDK's order. MATRIX-170: from
    /// `RoomAccountNames.topLevelSpaces`, which holds the cached list until
    /// the SDK gives its list.
    private static func joinedSpaces(client: MatrixClient) -> [ChatListRailSpace] {
        client.roomAccounts.topLevelSpaces.map { space in
            ChatListRailSpace(id: space.id, name: space.name, avatarUrl: space.avatarUrl)
        }
    }

    /// The rail's space items: the top-level joined spaces that hold a chat,
    /// each with its unread mark.
    ///
    /// The unread mark follows the label items: a count of the unread chats
    /// that are not muted (by the room's own mode or by its labels), else a
    /// dot for other unread activity.
    static func spaces(client: MatrixClient?) -> [ChatListRailSpace] {
        guard let client else { return [] }
        let labelMuted = client.labels?.document.labelMutedRoomIds ?? []
        let unread = client.dockBadge.unreadChats.chats.mapValues { chat in
            ChatListUnread(
                numUnreadMessages: chat.numUnreadMessages,
                numUnreadNotifications: chat.numUnreadNotifications,
                numUnreadMentions: 0,
                isMarkedUnread: chat.isMarkedUnread,
                isMuted: chat.isMuted,
                isMutedByLabel: labelMuted.contains(chat.roomId)
            )
        }
        return ChatListRailSpace.items(
            joined: joinedSpaces(client: client),
            spaces: client.roomAccounts.spaceMap,
            chatIds: chatIds(client: client),
            unread: unread
        )
    }

    /// The filter the window shows: its rail selection, or the Inbox when
    /// the selected label or space is not on the rail.
    static func filter(client: MatrixClient?, windowState: WindowState) -> ChatListRailFilter {
        guard let client else { return .inbox }
        let selection = windowState.railFilter
        guard case .space = selection else {
            return selection.resolved(labels: client.labels?.document ?? ChatLabelDocument(), spaceIds: [])
        }
        let withChats = client.roomAccounts.spaceMap.roomsBySpace(among: chatIds(client: client))
        let railSpaceIds = Set(joinedSpaces(client: client).map(\.id).filter { withChats[$0] != nil })
        return selection.resolved(labels: client.labels?.document ?? ChatLabelDocument(), spaceIds: railSpaceIds)
    }

    /// The room IDs the SDK room list is narrowed to for the window's
    /// filter, or nil for the Inbox.
    static func narrowingRoomIds(client: MatrixClient?, windowState: WindowState) -> [String]? {
        guard let client else { return nil }
        return filter(client: client, windowState: windowState).narrowingRoomIds(
            labels: client.labels?.document ?? ChatLabelDocument(),
            spaces: client.roomAccounts.spaceMap,
            chatIds: chatIds(client: client)
        )
    }

    /// The chat list's title for the window's filter: the space's or the
    /// label's name, or nil for the Inbox.
    static func filterName(client: MatrixClient?, windowState: WindowState) -> String? {
        switch filter(client: client, windowState: windowState) {
        case .inbox:
            nil
        case let .space(id):
            client?.roomAccounts.topLevelSpaces.first { $0.id == id }?.name
        case let .label(id):
            client?.labels?.document.label(id: id)?.name
        }
    }
}

/// The rooms of one space (MATRIX-167): what the sidebar's Spaces section
/// showed, opened from the rail item's "Browse Rooms…".
///
/// A click on a room opens it in the window and closes the sheet.
struct SpaceBrowserSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.dismiss) private var dismiss

    let request: SpaceBrowserRequest

    private var space: SidebarSpaceRoom? {
        appState.matrixClient?.spaceService?.spaceRooms.first { $0.id == request.spaceId }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { nil },
            set: { itemId in
                guard let itemId else { return }
                let document = appState.matrixClient?.mergedChats?.document ?? MergedChatDocument()
                windowState.chatSelection = MergedChatSelection.selection(forItemId: itemId, document: document)
                dismiss()
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let space {
                List(selection: selection) {
                    SpaceDisclosureGroup(space: space, isExpanded: true)
                }
            } else {
                ContentUnavailableView("This space is no longer joined", systemImage: "square.grid.2x2")
                    .frame(maxHeight: .infinity)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 420, height: 480)
    }
}

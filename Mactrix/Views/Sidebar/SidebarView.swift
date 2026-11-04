import MatrixRustSDK
import Models
import SwiftUI
import Tokens
import UI

/// The sidebar: Beeper's inbox model (MATRIX-67).
///
/// Favourites sit in a pinned grid at the top; every other room is one
/// recency-ordered list of two-line rows. The order is the SDK room list's
/// own — it already sorts by recency — so the view never re-sorts. Which
/// rooms the list holds is the window's chat-list filter, applied by the SDK.
struct SidebarView: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState
    @Environment(\.appearsActive) private var appearsActive

    /// Rooms in SDK order, without spaces: those live in the Spaces section.
    private var chatRooms: [SidebarRoom] {
        (appState.matrixClient?.rooms ?? []).filter { !$0.room.isSpace() }
    }

    var spaces: [SidebarSpaceRoom] {
        appState.matrixClient?.spaceService?.spaceRooms ?? []
    }

    private var pinnedColumns: [GridItem] {
        [GridItem(.adaptive(minimum: ChatListToken.pinnedTileMinWidth), spacing: 0)]
    }

    var body: some View {
        @Bindable var windowState = windowState
        let rooms = chatRooms
        let favorites = rooms.filter { $0.roomInfo?.isFavourite == true }
        let inbox = rooms.filter { $0.roomInfo?.isFavourite != true }
        let now = Date.now

        List(selection: $windowState.selectedRoomId) {
            SidebarSyncStateView()

            SessionVerificationStatusView()

            if !favorites.isEmpty {
                // Tiles are buttons, not List rows: a grid cell cannot carry
                // List selection, so each tile draws its own selected state.
                LazyVGrid(columns: pinnedColumns, spacing: 0) {
                    ForEach(favorites) { room in
                        PinnedChatTile(
                            model: room.chatListRow(now: now),
                            isSelected: windowState.selectedRoomId == room.id,
                            imageLoader: appState.matrixClient
                        ) {
                            windowState.selectedRoomId = room.id
                        }
                        .contextMenu {
                            RoomContextMenu(room: room)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .selectionDisabled()
            }

            Section {
                ForEach(inbox) { room in
                    ChatListRow(model: room.chatListRow(now: now), imageLoader: appState.matrixClient)
                        // The row pads itself to the Beeper geometry.
                        .listRowInsets(EdgeInsets())
                        .contextMenu {
                            RoomContextMenu(room: room)
                        }
                }
            } header: {
                Text(windowState.chatListFilter.title)
            }

            Section("Spaces", isExpanded: $windowState.sidebarSections.spaces) {
                ForEach(spaces) { space in
                    SpaceDisclosureGroup(space: space)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: nil)
        .toolbar {
            chatListFilterMenu
            AppCommands.createRoomButton(windowState: windowState)
        }
        // Keyed on the client, so a client created after login or a session
        // reset picks up this window's filter too.
        .task(id: appState.matrixClient.map(ObjectIdentifier.init)) {
            appState.matrixClient?.setChatListFilter(windowState.chatListFilter)
        }
        .onChange(of: windowState.chatListFilter) { _, filter in
            appState.matrixClient?.setChatListFilter(filter)
        }
        // The SDK filter is per client: when several windows chose different
        // filters, the active one wins.
        .onChange(of: appearsActive) { _, active in
            guard active else { return }
            appState.matrixClient?.setChatListFilter(windowState.chatListFilter)
        }
    }

    private var chatListFilterMenu: some View {
        @Bindable var windowState = windowState
        let isFiltered = windowState.chatListFilter != .inbox

        return Menu {
            Picker("Show", selection: $windowState.chatListFilter) {
                ForEach(ChatListFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(
                "Filter Chats",
                systemImage: isFiltered
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .help("Filter chats: \(windowState.chatListFilter.title)")
    }
}

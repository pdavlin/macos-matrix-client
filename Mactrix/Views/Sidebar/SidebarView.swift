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
///
/// MATRIX-77: the label rail sits at the leading edge. A selected label
/// narrows the SDK filter to its rooms; the Inbox drops rooms of hidden
/// labels here, because the SDK has no negated identifiers filter.
struct SidebarView: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState
    @Environment(\.appearsActive) private var appearsActive

    /// Rooms in SDK order, without spaces: those live in the Spaces section.
    private var chatRooms: [SidebarRoom] {
        (appState.matrixClient?.rooms ?? []).filter { !$0.room.isSpace() }
    }

    private var labels: LabelsModel? {
        appState.matrixClient?.labels
    }

    private var labelDocument: ChatLabelDocument {
        labels?.document ?? ChatLabelDocument()
    }

    /// The window's label, if the labels still hold it.
    private var selectedLabel: ChatLabel? {
        windowState.selectedLabelId.flatMap(labelDocument.label(id:))
    }

    var spaces: [SidebarSpaceRoom] {
        appState.matrixClient?.spaceService?.spaceRooms ?? []
    }

    private var pinnedColumns: [GridItem] {
        [GridItem(.adaptive(minimum: ChatListToken.pinnedTileMinWidth), spacing: 0)]
    }

    var body: some View {
        @Bindable var windowState = windowState

        HStack(spacing: 0) {
            SidebarLabelRail(labels: labels)
            Divider()
            chatList
        }
        .navigationSplitViewColumnWidth(min: 240 + LabelToken.railWidth, ideal: 320 + LabelToken.railWidth, max: nil)
        .toolbar {
            chatListFilterMenu
            AppCommands.createRoomButton(windowState: windowState)
        }
        // Keyed on the client, so a client created after login or a session
        // reset picks up this window's filter too.
        .task(id: appState.matrixClient.map(ObjectIdentifier.init)) {
            applyChatListFilter()
        }
        .onChange(of: windowState.chatListFilter) {
            applyChatListFilter()
        }
        // MATRIX-77: a label's room set changes when it is edited, here or
        // on another device.
        .onChange(of: selectedLabel?.rooms) {
            applyChatListFilter()
        }
        // The SDK filter is per client: when several windows chose different
        // filters, the active one wins. Labels have no change listener, so
        // activation is also when another window's or device's edits arrive.
        .onChange(of: appearsActive) { _, active in
            guard active else { return }
            applyChatListFilter()
            Task { await labels?.refresh() }
        }
        .sheet(item: $windowState.labelEditor) { request in
            LabelEditorHost(request: request)
        }
    }

    private func applyChatListFilter() {
        appState.matrixClient?.setChatListFilter(windowState.chatListFilter, labelRooms: selectedLabel?.rooms)
    }

    private var listTitle: String {
        guard let selectedLabel else { return windowState.chatListFilter.title }
        if windowState.chatListFilter == .inbox {
            return selectedLabel.name
        }
        return "\(selectedLabel.name) · \(windowState.chatListFilter.title)"
    }

    private var chatList: some View {
        @Bindable var windowState = windowState
        let document = labelDocument
        let hidden = selectedLabel == nil ? document.inboxHiddenRoomIds : []
        let mutedByLabel = document.labelMutedRoomIds
        let rooms = chatRooms.filter { !hidden.contains($0.id) }
        let favorites = rooms.filter { $0.roomInfo?.isFavourite == true }
        let inbox = rooms.filter { $0.roomInfo?.isFavourite != true }
        let now = Date.now

        return List(selection: $windowState.selectedRoomId) {
            SidebarSyncStateView()

            SessionVerificationStatusView()

            if !favorites.isEmpty {
                // Tiles are buttons, not List rows: a grid cell cannot carry
                // List selection, so each tile draws its own selected state.
                LazyVGrid(columns: pinnedColumns, spacing: 0) {
                    ForEach(favorites) { room in
                        PinnedChatTile(
                            model: room.chatListRow(now: now, mutedByLabel: mutedByLabel.contains(room.id)),
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
                    ChatListRow(
                        model: room.chatListRow(now: now, mutedByLabel: mutedByLabel.contains(room.id)),
                        imageLoader: appState.matrixClient
                    )
                    // The row pads itself to the Beeper geometry.
                    .listRowInsets(EdgeInsets())
                    .contextMenu {
                        RoomContextMenu(room: room)
                    }
                }
            } header: {
                Text(listTitle)
            }

            Section("Spaces", isExpanded: $windowState.sidebarSections.spaces) {
                ForEach(spaces) { space in
                    SpaceDisclosureGroup(space: space)
                }
            }
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

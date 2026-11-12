import Core
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

    /// The column's narrowest width: the chat list plus the label rail.
    private static let minimumWidth: CGFloat = 240 + LabelToken.railWidth
    /// The column's width before the user first resizes it.
    private static let defaultWidth: CGFloat = 320 + LabelToken.railWidth

    /// Stores the column's width when the user resizes it (MATRIX-116).
    @State private var widthRecorder = SidebarWidthRecorder(minimumWidth: SidebarView.minimumWidth)
    /// The width the column starts at: the width the user last left a
    /// sidebar at. Read once per window, so the column's ideal does not move
    /// while the user drags the divider.
    @State private var initialWidth = CGFloat(
        SidebarWidthRecorder.idealWidth(minimumWidth: SidebarView.minimumWidth, defaultWidth: SidebarView.defaultWidth)
    )

    /// The chats a window's sidebar shows: the favourites grid, then the
    /// chat list (MATRIX-115), with merged chats folded in (MATRIX-141).
    ///
    /// The sidebar draws this and the Go menu's ⌘1…⌘9 and ⇧⌘] / ⇧⌘[ walk it
    /// (`GoNavigationPublisher`), so the two cannot disagree. Spaces are
    /// left out: they live in the Spaces section. The rules (filter, then
    /// merge, then split favourites) are in
    /// `ChatListMerging.visible(entries:labels:selectedLabelId:document:)`.
    ///
    /// - Parameter now: decides the rows' timestamp buckets.
    static func visibleChatList(client: MatrixClient?, windowState: WindowState, now: Date = .now) -> SidebarChatList {
        let chatRooms = (client?.rooms ?? []).filter { !$0.room.isSpace() }
        let labels = client?.labels?.document ?? ChatLabelDocument()
        let mutedByLabel = labels.labelMutedRoomIds
        // MATRIX-148: each row's account (its Slack workspace), for the badge.
        let accounts = client?.roomAccounts
        let entries = chatRooms.map { room in
            var entry = room.chatListEntry(now: now, mutedByLabel: mutedByLabel.contains(room.id))
            entry.row.account = accounts?.account(of: room.id, network: entry.row.network)
            return entry
        }
        let visible = ChatListMerging.visible(
            entries: entries,
            labels: labels,
            selectedLabelId: windowState.selectedLabelId,
            document: client?.mergedChats?.document ?? MergedChatDocument()
        )
        return SidebarChatList(visible: visible, rooms: chatRooms)
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
        .navigationSplitViewColumnWidth(min: Self.minimumWidth, ideal: initialWidth, max: nil)
        // MATRIX-148: read each room's account once; new rooms as they come.
        .task(id: appState.matrixClient?.rooms.count) {
            guard let client = appState.matrixClient else { return }
            client.loadRoomAccounts(client.rooms.map(\.id))
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { width in
            widthRecorder.record(width)
        })
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
            // MATRIX-140: merged chats have no change listener either.
            Task { await appState.matrixClient?.mergedChats?.refresh() }
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

    /// The List's selection: the selected row's ID, a room ID or a merged
    /// chat's ID (MATRIX-141). A click on a merged row selects the merged
    /// chat.
    private var listSelection: Binding<String?> {
        Binding(
            get: { windowState.chatSelection?.itemId },
            set: { itemId in
                let document = appState.matrixClient?.mergedChats?.document ?? MergedChatDocument()
                windowState.chatSelection = itemId.map { MergedChatSelection.selection(forItemId: $0, document: document) }
            }
        )
    }

    private var chatList: some View {
        @Bindable var windowState = windowState
        let chats = Self.visibleChatList(client: appState.matrixClient, windowState: windowState)
        let favorites = chats.visible.favorites
        let inbox = chats.visible.list
        let selectedItemId = windowState.chatSelection?.itemId

        return List(selection: listSelection) {
            SidebarSyncStateView()

            SessionVerificationStatusView()

            if !favorites.isEmpty {
                // Tiles are buttons, not List rows: a grid cell cannot carry
                // List selection, so each tile draws its own selected state.
                LazyVGrid(columns: pinnedColumns, spacing: 0) {
                    ForEach(favorites) { item in
                        PinnedChatTile(
                            model: item.row,
                            isSelected: selectedItemId == item.id,
                            imageLoader: appState.matrixClient
                        ) {
                            windowState.chatSelection = item.selection
                        }
                        // MATRIX-133: a visible row may load members for its
                        // bubble cluster.
                        .onAppear { chats.rooms(of: item).forEach { $0.chatListRowDidAppear() } }
                        .onDisappear { chats.rooms(of: item).forEach { $0.chatListRowDidDisappear() } }
                        .contextMenu {
                            ChatListItemContextMenu(item: item, chats: chats)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .selectionDisabled()
            }

            Section {
                ForEach(inbox) { item in
                    ChatListRow(model: item.row, imageLoader: appState.matrixClient)
                        // The row pads itself to the Beeper geometry. The macOS
                        // sidebar List still insets each row 16 pt on each side
                        // (measured for MATRIX-123), so the row adds no
                        // horizontal padding of its own.
                        .listRowInsets(EdgeInsets())
                        .onAppear { chats.rooms(of: item).forEach { $0.chatListRowDidAppear() } }
                        .onDisappear { chats.rooms(of: item).forEach { $0.chatListRowDidDisappear() } }
                        .contextMenu {
                            ChatListItemContextMenu(item: item, chats: chats)
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

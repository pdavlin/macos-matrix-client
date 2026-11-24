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
///
/// MATRIX-167: the joined spaces are rail items too. A selected space
/// narrows the SDK filter to its chats, as a label does. The rail has one
/// selection, `WindowState.railFilter`.
struct SidebarView: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState
    @Environment(\.appearsActive) private var appearsActive
    /// MATRIX-194: Settings > Appearance > "Show network badges".
    @AppStorage(NetworkBadgePreferences.storageKey) private var showsNetworkBadges = NetworkBadgePreferences.defaultValue

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
    /// The sidebar draws this and the Go menu's ⌘] / ⌘[ walk it (MATRIX-217)
    /// (`GoNavigationPublisher`), so the two cannot disagree. Space rooms
    /// are left out: a space is a rail filter. The rules (filter, then
    /// merge, then split favourites) are in
    /// `ChatListMerging.visible(entries:filter:labels:spaces:document:)`.
    ///
    /// - Parameter now: decides the rows' timestamp buckets.
    static func visibleChatList(client: MatrixClient?, windowState: WindowState, now: Date = .now) -> SidebarChatList {
        let chatRooms = (client?.rooms ?? []).filter { !$0.room.isSpace() }
        let labels = client?.labels?.document ?? ChatLabelDocument()
        let accounts = client?.roomAccounts
        let merges = client?.mergedChats?.document ?? MergedChatDocument()
        let inbox = client?.inbox?.document ?? InboxStateDocument()
        let placement = windowState.chatListFilter.inboxPlacement
        let merged = ChatListMerging.visible(
            entries: chatListEntries(client: client, rooms: chatRooms, now: now),
            filter: SidebarRail.filter(client: client, windowState: windowState),
            labels: labels,
            spaces: accounts?.spaceMap ?? RoomSpaceMap(),
            document: merges,
            // MATRIX-206, MATRIX-207: archived and snoozed chats show under
            // their own list filter only.
            inbox: inbox,
            placement: placement
        )
        // MATRIX-212: a clock on each chat with a scheduled message.
        let visible = merged.withScheduledMarks(roomIds: client?.scheduledMessages?.document.roomIds ?? [])
        guard placement == .snoozed else {
            return SidebarChatList(visible: visible, rooms: chatRooms)
        }
        // MATRIX-207: each row says when its snooze ends.
        return SidebarChatList(visible: visible.withSnoozeNotes(inbox: inbox, merges: merges, now: now), rooms: chatRooms)
    }

    /// The chat-list entries of the sidebar's chat rooms, in SDK order. The
    /// broadcast reads them too (MATRIX-172).
    ///
    /// - Parameter rooms: the client's rooms without the spaces.
    static func chatListEntries(client: MatrixClient?, rooms: [SidebarRoom], now: Date = .now) -> [ChatListEntry] {
        let mutedByLabel = client?.labels?.document.labelMutedRoomIds ?? []
        // MATRIX-148: each row's account (its Slack workspace), for the badge.
        let accounts = client?.roomAccounts
        return rooms.map { room in
            var entry = room.chatListEntry(now: now, mutedByLabel: mutedByLabel.contains(room.id))
            entry.row.account = accounts?.account(of: room.id, network: entry.row.network)
            return entry
        }
    }

    private var labels: LabelsModel? {
        appState.matrixClient?.labels
    }

    /// The rooms the SDK list is narrowed to: the selected label's or
    /// space's rooms, or nil for the Inbox. MATRIX-206: for the Archived
    /// filter, only the archived rooms among them.
    private var narrowingRoomIds: [String]? {
        SidebarInbox.narrowingRoomIds(client: appState.matrixClient, windowState: windowState)
    }

    /// The account's chat rooms, for the room-to-space map.
    private var accountChatIds: Set<String> {
        appState.matrixClient.map(SidebarRail.chatIds(client:)) ?? []
    }

    var body: some View {
        @Bindable var windowState = windowState

        HStack(spacing: 0) {
            SidebarLabelRail(labels: labels)
            Divider()
            // MATRIX-226: the active filter chip, above the list.
            VStack(spacing: 0) {
                SidebarFilterHeader()
                chatList
                    .environment(\.showsNetworkBadges, showsNetworkBadges)
            }
        }
        // MATRIX-227: a rail item's name after a Go-menu key.
        .modifier(SidebarRailNamePeek())
        .navigationSplitViewColumnWidth(min: Self.minimumWidth, ideal: initialWidth, max: nil)
        // MATRIX-148: read each room's account once; new rooms as they come.
        // MATRIX-167: also for the chats the window's filter leaves out, so
        // the rail's spaces do not depend on the filter.
        .task(id: accountChatIds.count) {
            guard let client = appState.matrixClient else { return }
            client.loadRoomAccounts(client.rooms.map(\.id) + accountChatIds.sorted())
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
        // on another device. MATRIX-167: a space's room set changes when
        // the space graph loads or a chat joins the space, and the rail
        // selection changes it too.
        .onChange(of: narrowingRoomIds) {
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
            // MATRIX-206: nor do the inbox states.
            Task { await appState.matrixClient?.inbox?.refresh() }
            // MATRIX-208: nor do bookmarks.
            Task { await appState.matrixClient?.bookmarks?.refresh() }
            // MATRIX-212: nor do scheduled messages.
            Task { await appState.matrixClient?.scheduledMessages?.refresh() }
        }
        .sheet(item: $windowState.labelEditor) { request in
            LabelEditorHost(request: request)
        }
        .sheet(item: $windowState.spaceBrowser) { request in
            SpaceBrowserSheet(request: request)
        }
        .sheet(item: $windowState.broadcast) { request in
            BroadcastHost(request: request)
        }
        .sheet(item: $windowState.inboxDatePicker) { request in
            InboxDatePickerHost(request: request)
        }
        // MATRIX-222.
        .modifier(ArchiveAllReadConfirmation())
    }

    private func applyChatListFilter() {
        // `labelRooms` carries a space's chats too: the SDK narrowing is the
        // same for both.
        appState.matrixClient?.setChatListFilter(windowState.chatListFilter, labelRooms: narrowingRoomIds)
    }

    /// The row's hover button (MATRIX-222).
    private func rowAction(for item: ChatListItem) -> ChatListRowAction? {
        SidebarInbox.rowAction(for: item, client: appState.matrixClient, windowState: windowState)
    }

    private var listTitle: String {
        guard let name = SidebarRail.filterName(client: appState.matrixClient, windowState: windowState) else {
            return windowState.chatListFilter.title
        }
        if windowState.chatListFilter == .inbox {
            return name
        }
        return "\(name) · \(windowState.chatListFilter.title)"
    }

    /// The List's selection: the selected row's ID, a room ID or a merged
    /// chat's ID (MATRIX-141). A click on a merged row selects the merged
    /// chat.
    ///
    /// MATRIX-188: the List does not tell a click from an arrow key, so the
    /// current input event does. A click moves the focus to the composer;
    /// an arrow key keeps it in the list.
    private var listSelection: Binding<String?> {
        Binding(
            get: { windowState.chatSelection?.itemId },
            set: { itemId in
                let document = appState.matrixClient?.mergedChats?.document ?? MergedChatDocument()
                let selection = itemId.map { MergedChatSelection.selection(forItemId: $0, document: document) }
                // The List can write back the selection it shows. That is no
                // user change, and it must not drop a focus request that
                // another path (⌘K, a notification) made.
                guard selection != windowState.chatSelection else { return }
                windowState.open(
                    selection,
                    from: ChatOpenSource(listSelectionEvent: Self.listSelectionEvent(NSApp.currentEvent))
                )
            }
        )
    }

    /// The kind of the input event behind a List selection change
    /// (MATRIX-188). `NSApp.currentEvent` stays the last event AppKit took
    /// from the queue, so a key's release also counts as the keyboard.
    private static func listSelectionEvent(_ event: NSEvent?) -> ListSelectionEvent {
        switch event?.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .otherMouseDown, .otherMouseUp:
            .pointer
        case .keyDown, .keyUp, .flagsChanged:
            .keyboard
        default:
            .other
        }
    }

    private var chatList: some View {
        // MATRIX-157: the observed clock makes the row timestamps change
        // bucket when the day changes, not only when a room changes.
        let chats = Self.visibleChatList(
            client: appState.matrixClient,
            windowState: windowState,
            now: CurrentDay.shared.observedNow
        )
        let favorites = chats.visible.favorites
        let inbox = chats.visible.list
        let selectedItemId = windowState.chatSelection?.itemId
        // MATRIX-168: nil for the Inbox and for a filter with no chat.
        // MATRIX-172: it does not depend on the chats the list shows.
        // MATRIX-226: no title under the filter chip, which names the filter.
        let header = ChatListSectionHeader(
            listTitle: listTitle,
            activeFilter: SidebarFilterHeader.activeFilter(client: appState.matrixClient, windowState: windowState),
            broadcastName: SidebarBroadcast.filterName(client: appState.matrixClient, windowState: windowState)
        )

        return List(selection: listSelection) {
            SidebarSyncStateView()

            SessionVerificationStatusView()

            if !favorites.isEmpty {
                // Tiles are buttons, not List rows: a grid cell cannot carry
                // List selection, so each tile draws its own selected state.
                PinnedChatGrid(favorites) { item in
                    PinnedChatTile(
                        model: item.row,
                        isSelected: selectedItemId == item.id,
                        imageLoader: appState.matrixClient
                    ) {
                        windowState.open(item.selection, from: .click)
                    }
                    // MATRIX-133: a visible row may load members for its
                    // bubble cluster.
                    .onAppear { chats.rooms(of: item).forEach { $0.chatListRowDidAppear() } }
                    .onDisappear { chats.rooms(of: item).forEach { $0.chatListRowDidDisappear() } }
                    .contextMenu {
                        ChatListItemContextMenu(item: item, chats: chats)
                    }
                }
                .listRowInsets(EdgeInsets())
                .selectionDisabled()
            }

            // MATRIX-226: an empty header would draw an empty band, so the
            // section has none then.
            if header.isEmpty {
                Section {
                    chatRows(inbox, chats: chats)
                }
            } else {
                Section {
                    chatRows(inbox, chats: chats)
                } header: {
                    sectionHeader(header)
                }
            }
        }
        // MATRIX-196: the system fade where the list runs under the toolbar.
        .scrollEdgeEffectStyle(ScrollEdgeToken.sidebarTop, for: .top)
        // MATRIX-206: "Archived <chat>" with Undo.
        .overlay(alignment: .bottom) {
            InboxNoticeOverlay()
        }
        .animation(.easeOut(duration: 0.2), value: windowState.inboxNotice?.id)
        // MATRIX-188: Return on the selected row moves the focus to the
        // chat's composer.
        .onKeyPress(.return) {
            windowState.requestComposerFocus(from: .returnKey) ? .handled : .ignored
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

            Divider()

            // MATRIX-222.
            ArchiveAllReadButton()
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

// MARK: - Chat list section

private extension SidebarView {
    /// The chat list's rows below the pinned grid.
    func chatRows(_ inbox: [ChatListItem], chats: SidebarChatList) -> some View {
        ForEach(inbox) { item in
            // MATRIX-222: Archive (Unarchive) under the pointer.
            ChatListRow(model: item.row, imageLoader: appState.matrixClient, primaryAction: rowAction(for: item))
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
    }

    /// The section header: the list's title (none under the filter chip,
    /// MATRIX-226) and the Broadcast button at the trailing edge.
    func sectionHeader(_ header: ChatListSectionHeader) -> some View {
        HStack(spacing: 6) {
            if let title = header.title {
                Text(title)
            }
            Spacer(minLength: 0)
            // MATRIX-168: shows for a label or a space with chats.
            if let broadcastName = header.broadcastName {
                Button {
                    windowState.broadcast = SidebarBroadcast.request(
                        client: appState.matrixClient, windowState: windowState
                    )
                } label: {
                    Label("Broadcast…", systemImage: "megaphone")
                }
                .buttonStyle(.borderless)
                .help("Send one message to the chats of \(broadcastName)")
            }
        }
    }
}

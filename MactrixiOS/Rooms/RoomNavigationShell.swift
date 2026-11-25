import Core
import MatrixRustSDK
import Models
import SwiftUI
import UI
import UIKit

/// The signed-in navigation shell over Core's live room list. A room opens
/// as its live timeline and composer (MATRIX-102).
///
/// MATRIX-247: the list reaches every chat. The search field searches every
/// joined room through a `QuickSwitcherRoomDirectory`, as ⌘K does on the
/// Mac; the directory lives while the search field is open. The toolbar menu
/// switches the client's list between the Inbox and Low Priority. The last
/// row of the list loads the next page of rooms.
struct SignedInRoomNavigation: View {
    let matrixClient: MatrixClient

    @Environment(\.scenePhase) private var scenePhase

    /// This scene's list filter, as the Mac keeps one per window. The
    /// client has one list for every scene, so a scene applies its filter
    /// when the filter changes and when the scene becomes active.
    @SceneStorage("chatListFilter") private var storedFilter = ChatListFilter.inbox.rawValue

    @State private var isSearching = false
    @State private var directory: QuickSwitcherRoomDirectory?

    var body: some View {
        let imageLoader = RoomListImageLoader(matrixClient: matrixClient)
        // Read here, so a new directory renders the shell again.
        let directory = directory
        RoomNavigationShell(
            rooms: matrixClient.rooms,
            isLoading: RoomListLoading.isLoading(matrixClient.roomListServiceState),
            imageLoader: imageLoader,
            filter: filter,
            search: RoomListSearch(
                results: { query in directory.flatMap { ChatListSearch.results(in: $0.rooms, query: query) } },
                setActive: { isSearching = $0 }
            ),
            loadMore: matrixClient.loadMoreRooms,
            roomOutsideList: roomOutsideList
        ) { sidebarRoom in
            LiveRoomScreen(sidebarRoom: sidebarRoom, imageLoader: imageLoader)
        }
        .onChange(of: storedFilter, initial: true) {
            applyFilter()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { applyFilter() }
        }
        .task(id: isSearching) {
            await updateDirectory()
        }
        .onDisappear {
            self.directory?.stop()
        }
    }

    private var filter: Binding<ChatListFilter> {
        Binding(
            get: { ChatListFilter.iosChoice(restoring: storedFilter) },
            set: { storedFilter = $0.rawValue }
        )
    }

    private func applyFilter() {
        matrixClient.setChatListFilter(ChatListFilter.iosChoice(restoring: storedFilter))
    }

    /// A search result outside the loaded list: the Mac's fallback for a
    /// room that the room list has not delivered (`MainView`).
    private func roomOutsideList(_ roomID: String) -> SidebarRoom? {
        (try? matrixClient.client.getRoom(roomId: roomID)).map(SidebarRoom.init(room:))
    }

    /// Opens a new directory when the search field opens, and closes it when
    /// the field closes, as the Mac makes one per ⌘K sheet.
    private func updateDirectory() async {
        directory?.stop()
        directory = nil
        guard isSearching else { return }
        let directory = QuickSwitcherRoomDirectory()
        self.directory = directory
        directory.seed(sidebarRooms: matrixClient.rooms)
        guard let roomListService = matrixClient.roomListService else { return }
        await directory.start(roomListService: roomListService)
        // The field closed while the list opened: the next task already
        // ran, so close this directory here.
        if Task.isCancelled { directory.stop() }
    }
}

/// The chat search the shell offers (MATRIX-247). The app searches every
/// joined room; tests and previews pass fixed results.
struct RoomListSearch {
    /// The results for a query, best first, or nil to show the list.
    let results: @MainActor (String) -> [QuickSwitcherRoom]?
    /// Called with true when the search field opens, false when it closes.
    let setActive: @MainActor (Bool) -> Void
}

/// Whether an empty room list means "still loading" or "no rooms".
enum RoomListLoading {
    static func isLoading(_ state: RoomListServiceState?) -> Bool {
        switch state {
        case .running, .error, .terminated:
            false
        case .initial, .settingUp, .recovering, nil:
            true
        }
    }
}

/// iPhone: a `NavigationStack`; every other idiom: a `NavigationSplitView`.
enum RoomNavigationLayout {
    static func usesStack(for idiom: UIUserInterfaceIdiom) -> Bool {
        idiom == .phone
    }
}

/// iPhone: a `NavigationStack` with the room list as root. iPad: a
/// `NavigationSplitView` with the room list as sidebar; it collapses to a
/// stack by itself when the iPad window is compact. The choice is by device
/// idiom, not size class, so a window resize never swaps the view tree and
/// drops the navigation state.
///
/// A selected room shows `roomDetail` for its list item: the live timeline in
/// the app, a fixture conversation in tests and previews. The detail lives as
/// long as the room stays open: popped off the iPhone stack, or replaced by a
/// new iPad selection, its state (the room's timeline) is released.
struct RoomNavigationShell<Item: RoomListItem, RoomDetail: View>: View {
    let rooms: [Item]
    let isLoading: Bool
    let imageLoader: (any UI.ImageLoader)?
    let usesStack: Bool
    /// The list filter and its toolbar menu (MATRIX-247). Nil: no menu.
    private let filter: Binding<ChatListFilter>?
    /// The search field (MATRIX-247). Nil: no field.
    private let search: RoomListSearch?
    /// Loads the next page of rooms when the list's last row shows.
    private let loadMore: (@MainActor () -> Void)?
    /// The item for a room that is not in `rooms`, for a picked search
    /// result. Nil: such a room shows the placeholder.
    private let roomOutsideList: (@MainActor (String) -> Item?)?
    private let roomDetail: (Item) -> RoomDetail

    @State private var selection: String?
    @State private var path: [String]
    @State private var showsSettings = false
    @State private var query = ""
    @State private var isSearchPresented = false

    /// - Parameters:
    ///   - openedRoomID: A room to show at first appearance, as if the user
    ///     selected it. Tests use it; the app starts on the list.
    ///   - roomDetail: The detail screen for one selected room.
    init(
        rooms: [Item],
        isLoading: Bool,
        imageLoader: (any UI.ImageLoader)?,
        usesStack: Bool = RoomNavigationLayout.usesStack(for: UIDevice.current.userInterfaceIdiom),
        openedRoomID: String? = nil,
        filter: Binding<ChatListFilter>? = nil,
        search: RoomListSearch? = nil,
        loadMore: (@MainActor () -> Void)? = nil,
        roomOutsideList: (@MainActor (String) -> Item?)? = nil,
        @ViewBuilder roomDetail: @escaping (Item) -> RoomDetail
    ) {
        self.rooms = rooms
        self.isLoading = isLoading
        self.imageLoader = imageLoader
        self.usesStack = usesStack
        self.filter = filter
        self.search = search
        self.loadMore = loadMore
        self.roomOutsideList = roomOutsideList
        self.roomDetail = roomDetail
        _path = State(initialValue: usesStack ? openedRoomID.map { [$0] } ?? [] : [])
        _selection = State(initialValue: usesStack ? nil : openedRoomID)
    }

    var body: some View {
        Group {
            if usesStack {
                NavigationStack(path: $path) {
                    roomList(selection: nil)
                        .navigationDestination(for: String.self) { roomID in
                            detail(for: roomID)
                        }
                }
            } else {
                NavigationSplitView {
                    roomList(selection: $selection)
                } detail: {
                    if let selection {
                        NavigationStack {
                            detail(for: selection)
                        }
                        // A new selection is a new view tree: the old room's
                        // detail state is released, as the Mac drops its
                        // `LiveTimeline` when the selection changes.
                        .id(selection)
                    } else {
                        ContentUnavailableView(
                            "No Room Selected",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Select a room or direct message.")
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
    }

    private func roomList(selection: Binding<String?>?) -> some View {
        let shownFilter = filter?.wrappedValue ?? .inbox
        return searchable(
            RoomListView(
                rooms: rooms,
                searchResults: search?.results(query),
                isLoading: isLoading,
                imageLoader: imageLoader,
                selection: selection,
                filter: shownFilter,
                loadMore: loadMore
            )
            .navigationTitle(shownFilter.iosListTitle)
            .toolbar {
                if let filter {
                    ToolbarItem(placement: .topBarLeading) {
                        RoomListFilterMenu(filter: filter)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        showsSettings = true
                    }
                    .accessibilityIdentifier("settingsButton")
                }
            }
        )
    }

    /// The list with the search field on the list's navigation bar, when
    /// the shell has a search.
    @ViewBuilder
    private func searchable(_ list: some View) -> some View {
        if let search {
            list
                .searchable(text: $query, isPresented: $isSearchPresented, prompt: "Search chats")
                .onChange(of: isSearchPresented) {
                    search.setActive(isSearchPresented)
                }
        } else {
            list
        }
    }

    private func detail(for roomID: String) -> some View {
        RoomDetailHost(roomID: roomID, rooms: rooms, roomOutsideList: roomOutsideList, content: roomDetail)
            .environment(\.closeRoom, closeAction(for: roomID))
    }

    /// Closes `roomID` if it is still the open room: pops it off the iPhone
    /// stack, or clears the iPad selection (MATRIX-104).
    private func closeAction(for roomID: String) -> CloseRoomAction {
        let path = $path
        let selection = $selection
        return CloseRoomAction {
            path.wrappedValue = RoomClosing.path(path.wrappedValue, closing: roomID)
            selection.wrappedValue = RoomClosing.selection(selection.wrappedValue, closing: roomID)
        }
    }
}

/// Closes the open room. The shell puts one in each room detail's
/// environment; outside the shell (previews, fixtures) it is nil.
struct CloseRoomAction {
    private let close: @MainActor () -> Void

    init(_ close: @escaping @MainActor () -> Void) {
        self.close = close
    }

    @MainActor
    func callAsFunction() {
        close()
    }
}

extension EnvironmentValues {
    /// The shell's action that closes the open room (MATRIX-104).
    @Entry var closeRoom: CloseRoomAction?
}

/// The navigation state after a room closes. A room that is no longer the
/// open one leaves the state as it is, so a late close (a call that returns
/// after the user moved on) never closes another room.
enum RoomClosing {
    /// The iPhone stack path: the closed room and everything pushed above it
    /// come off.
    static func path(_ path: [String], closing roomID: String) -> [String] {
        guard let index = path.firstIndex(of: roomID) else { return path }
        return Array(path[..<index])
    }

    /// The iPad selection: nil when the closed room was selected.
    static func selection(_ selection: String?, closing roomID: String) -> String? {
        selection == roomID ? nil : selection
    }
}

/// Which list item an open room's detail shows.
enum RoomDetailResolution {
    /// The room for `roomID`: the current list item, else the item the detail
    /// opened with.
    ///
    /// The fallback keeps an open room open while the room list service moves
    /// or briefly drops it (a `clear` then `append`). The Mac resolves the
    /// room once, when it is selected, and keeps it until the selection
    /// changes; this matches that. A room id that was never in the list
    /// resolves to nil.
    @MainActor
    static func room<Item: RoomListItem>(withID roomID: String, in rooms: [Item], opened: Item?) -> Item? {
        rooms.first { $0.id == roomID } ?? opened.flatMap { $0.id == roomID ? $0 : nil }
    }
}

/// One open room's detail: the content for its list item, or the
/// placeholder when the room id is not in the list.
///
/// MATRIX-247: a search result can name a room that is not in the list (a
/// later page, or Low Priority while the list shows the Inbox). The host
/// then asks `roomOutsideList` once, and keeps the item while the room is
/// open.
private struct RoomDetailHost<Item: RoomListItem, Content: View>: View {
    let roomID: String
    let rooms: [Item]
    let roomOutsideList: (@MainActor (String) -> Item?)?
    let content: (Item) -> Content

    @State private var opened: Item?
    @State private var askedOutsideList = false

    var body: some View {
        if let room = RoomDetailResolution.room(withID: roomID, in: rooms, opened: opened) {
            content(room)
                .onAppear {
                    if opened == nil { opened = room }
                }
        } else if let roomOutsideList, !askedOutsideList {
            Color(.systemBackground)
                .onAppear {
                    askedOutsideList = true
                    opened = roomOutsideList(roomID)
                }
        } else {
            RoomDetailPlaceholder()
        }
    }
}

/// Shown for a room id that is not in the room list: the room was left or
/// forgotten before it opened.
struct RoomDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Room Not Available",
            systemImage: "text.bubble",
            description: Text("This room is no longer in your room list.")
        )
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("roomDetailPlaceholder")
    }
}

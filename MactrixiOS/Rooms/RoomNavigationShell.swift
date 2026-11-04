import Core
import MatrixRustSDK
import SwiftUI
import UI
import UIKit

/// The signed-in navigation shell over Core's live room list. A room opens
/// as its live timeline and composer (MATRIX-102).
struct SignedInRoomNavigation: View {
    let matrixClient: MatrixClient

    var body: some View {
        let imageLoader = RoomListImageLoader(matrixClient: matrixClient)
        RoomNavigationShell(
            rooms: matrixClient.rooms,
            isLoading: RoomListLoading.isLoading(matrixClient.roomListServiceState),
            imageLoader: imageLoader
        ) { sidebarRoom in
            LiveRoomScreen(sidebarRoom: sidebarRoom, imageLoader: imageLoader)
        }
    }
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
    private let roomDetail: (Item) -> RoomDetail

    @State private var selection: String?
    @State private var path: [String]
    @State private var showsSettings = false

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
        @ViewBuilder roomDetail: @escaping (Item) -> RoomDetail
    ) {
        self.rooms = rooms
        self.isLoading = isLoading
        self.imageLoader = imageLoader
        self.usesStack = usesStack
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
        RoomListView(rooms: rooms, isLoading: isLoading, imageLoader: imageLoader, selection: selection)
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        showsSettings = true
                    }
                    .accessibilityIdentifier("settingsButton")
                }
            }
    }

    private func detail(for roomID: String) -> some View {
        RoomDetailHost(roomID: roomID, rooms: rooms, content: roomDetail)
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
private struct RoomDetailHost<Item: RoomListItem, Content: View>: View {
    let roomID: String
    let rooms: [Item]
    let content: (Item) -> Content

    @State private var opened: Item?

    var body: some View {
        if let room = RoomDetailResolution.room(withID: roomID, in: rooms, opened: opened) {
            content(room)
                .onAppear {
                    if opened == nil { opened = room }
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

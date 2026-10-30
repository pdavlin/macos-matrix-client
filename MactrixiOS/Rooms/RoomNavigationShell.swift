import Core
import MatrixRustSDK
import SwiftUI
import UI
import UIKit

/// The signed-in navigation shell over Core's live room list.
struct SignedInRoomNavigation: View {
    let matrixClient: MatrixClient

    var body: some View {
        RoomNavigationShell(
            rooms: matrixClient.rooms,
            isLoading: RoomListLoading.isLoading(matrixClient.roomListServiceState),
            imageLoader: RoomListImageLoader(matrixClient: matrixClient)
        )
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
struct RoomNavigationShell<Item: RoomListItem>: View {
    let rooms: [Item]
    let isLoading: Bool
    let imageLoader: (any UI.ImageLoader)?
    let usesStack: Bool

    @State private var selection: String?
    @State private var path: [String] = []
    @State private var showsSettings = false

    init(
        rooms: [Item],
        isLoading: Bool,
        imageLoader: (any UI.ImageLoader)?,
        usesStack: Bool = RoomNavigationLayout.usesStack(for: UIDevice.current.userInterfaceIdiom)
    ) {
        self.rooms = rooms
        self.isLoading = isLoading
        self.imageLoader = imageLoader
        self.usesStack = usesStack
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
        RoomDetailPlaceholder(
            roomID: roomID,
            title: rooms.first { $0.id == roomID }?.title ?? "Room"
        )
    }
}

/// Stands in for the room timeline until MATRIX-85 provides it.
struct RoomDetailPlaceholder: View {
    let roomID: String
    let title: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "text.bubble")
        } description: {
            Text("The timeline is not available on iOS yet.")
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("roomDetailPlaceholder")
    }
}

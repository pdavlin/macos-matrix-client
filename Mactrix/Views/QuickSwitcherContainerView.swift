import Core
import MatrixRustSDK
import Models
import SwiftUI
import UI

/// Wires `UI.QuickSwitcherView` to the signed-in client (MATRIX-114).
///
/// Rooms come from a `QuickSwitcherRoomDirectory` that lives as long as the
/// sheet: the sidebar's rooms at once, then every room. People come from
/// New Chat's directory search, and picking one goes through New Chat's
/// start path, which opens the existing DM or creates one. No SDK call is
/// made here that New Chat or the label sheet does not already make.
struct QuickSwitcherContainerView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.openWindow) private var openWindow

    /// Shows a room in this window (`MainView.openRoom`).
    let openRoom: (_ roomId: String) async -> Void

    @State private var directory = QuickSwitcherRoomDirectory()

    var body: some View {
        if let matrixClient = appState.matrixClient {
            UI.QuickSwitcherView(
                rooms: directory.rooms,
                currentRoomId: windowState.selectedRoomId,
                ownUserId: try? matrixClient.client.userId(),
                imageLoader: matrixClient,
                actions: .navigate(
                    searchPeople: { try await matrixClient.searchNewChatPeople(query: $0) },
                    openRoom: { await openRoom($0) },
                    startDirectChat: { userId in
                        let roomId = try await matrixClient.startDirectChat(userId: userId)
                        await openRoom(roomId)
                    },
                    // ⌥-Return: the room in its own window (MATRIX-116).
                    openRoomInNewWindow: { openWindow(value: RoomWindowID(roomId: $0)) }
                )
            )
            .onAppear {
                directory.seed(sidebarRooms: matrixClient.rooms)
            }
            .task {
                guard let roomListService = matrixClient.roomListService else { return }
                await directory.start(roomListService: roomListService)
            }
            .onDisappear {
                directory.stop()
            }
        } else {
            ContentUnavailableView("Not signed in", systemImage: "person.crop.circle.badge.exclamationmark")
                .frame(width: 560, height: 420)
        }
    }
}

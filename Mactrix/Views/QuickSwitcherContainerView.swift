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
///
/// In picker mode (MATRIX-112 forward) it offers rooms only and hands the
/// picked room ID back to the caller. A caller can narrow the rooms it
/// offers (MATRIX-141: the Merge Chats sheet offers one-to-one chats only).
struct QuickSwitcherContainerView: View {
    /// What the switcher is for.
    enum Purpose {
        /// ⌘K: shows a room in this window (`MainView.openRoom`).
        case navigate(openRoom: (_ roomId: String) async -> Void)
        /// Picker mode (MATRIX-112 forward): hands the picked room ID back.
        /// `currentRoomId` is the room the message comes from, listed last.
        /// Only rooms `isOffered` accepts are listed.
        case pickRoom(
            currentRoomId: String?,
            isOffered: @MainActor (QuickSwitcherRoom) -> Bool,
            onPick: @MainActor (_ roomId: String) -> Void
        )
    }

    /// MATRIX-147: each row shows what tells it from a chat with the same
    /// name (`MergedMemberIdentity.detail`). For the Merge Chats picker,
    /// where two chats with one person are the usual case.
    private var showsMemberDetails = false

    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.openWindow) private var openWindow

    let purpose: Purpose

    @State private var directory = QuickSwitcherRoomDirectory()

    /// ⌘K: picking a room shows it in this window.
    init(openRoom: @escaping (_ roomId: String) async -> Void) {
        self.purpose = .navigate(openRoom: openRoom)
    }

    /// Picker mode: rooms only, and the picked room goes to `onPick`.
    ///
    /// - Parameters:
    ///   - currentRoomId: the room the pick starts from, listed last.
    ///   - isOffered: the rooms to list. All rooms by default.
    ///   - onPick: gets the picked room ID. The switcher then closes.
    init(
        pickRoomFrom currentRoomId: String?,
        offering isOffered: @escaping @MainActor (QuickSwitcherRoom) -> Bool = { _ in true },
        showsMemberDetails: Bool = false,
        onPick: @escaping @MainActor (_ roomId: String) -> Void
    ) {
        self.showsMemberDetails = showsMemberDetails
        self.purpose = .pickRoom(currentRoomId: currentRoomId, isOffered: isOffered, onPick: onPick)
    }

    var body: some View {
        if let matrixClient = appState.matrixClient {
            UI.QuickSwitcherView(
                rooms: detailedRooms(matrixClient: matrixClient),
                currentRoomId: currentRoomId,
                ownUserId: try? matrixClient.client.userId(),
                imageLoader: matrixClient,
                actions: actions(matrixClient: matrixClient)
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
            .task(id: showsMemberDetails ? offeredRooms.map(\.id) : []) {
                guard showsMemberDetails else { return }
                matrixClient.loadRoomAccounts(offeredRooms.map(\.id))
            }
        } else {
            ContentUnavailableView("Not signed in", systemImage: "person.crop.circle.badge.exclamationmark")
                .frame(width: 560, height: 420)
        }
    }

    private var currentRoomId: String? {
        switch purpose {
        case .navigate: windowState.selectedRoomId
        case let .pickRoom(currentRoomId, _, _): currentRoomId
        }
    }

    /// Every room in ⌘K; the rooms the caller accepts in picker mode.
    private var offeredRooms: [QuickSwitcherRoom] {
        switch purpose {
        case .navigate: directory.rooms
        case let .pickRoom(_, isOffered, _): directory.rooms.filter(isOffered)
        }
    }

    /// The offered rooms, each with its member detail when the picker shows
    /// them: the network and the account ("Slack • DevObsessed"). One
    /// dictionary lookup per row.
    private func detailedRooms(matrixClient: MatrixClient) -> [QuickSwitcherRoom] {
        let rooms = offeredRooms
        guard showsMemberDetails else { return rooms }
        let names = matrixClient.roomAccounts.names
        return rooms.map { room in
            var room = room
            room.detail = MergedMemberIdentity(
                network: room.network,
                parentNames: names[room.id] ?? [],
                peerUserId: nil,
                roomName: nil
            ).detail
            return room
        }
    }

    private func actions(matrixClient: MatrixClient) -> UI.QuickSwitcherActions {
        switch purpose {
        case let .navigate(openRoom):
            .navigate(
                searchPeople: { try await matrixClient.searchNewChatPeople(query: $0) },
                openRoom: { await openRoom($0) },
                startDirectChat: { userId in
                    let roomId = try await matrixClient.startDirectChat(userId: userId)
                    await openRoom(roomId)
                },
                // ⌥-Return: the room in its own window (MATRIX-116).
                openRoomInNewWindow: { openWindow(value: RoomWindowID(roomId: $0)) }
            )
        case let .pickRoom(_, _, onPick):
            .picker(onPick: onPick)
        }
    }
}

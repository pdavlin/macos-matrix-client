import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI

struct SpaceDisclosureGroup: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    @State var space: SidebarSpaceRoom
    @State private var isExpanded: Bool = false

    var loadingRooms: some View {
        Label {
            Text("Loading rooms")
                .foregroundStyle(.secondary)
        } icon: {
            ProgressView().scaleEffect(0.5)
        }
    }

    var spaceRow: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            switch space.children {
            case .loading:
                loadingRooms
            case let .loaded(children):
                if children.paginationState == .loading {
                    loadingRooms
                } else {
                    ForEach(children.rooms) { room in
                        SpaceDisclosureGroup(space: room)
                    }
                }
            case let .error(error):
                Text("Error: \(error.localizedDescription)")
                    .foregroundStyle(Color.red)
                    .textSelection(.enabled)
            }
        } label: {
            roomRow
        }
        .task(id: isExpanded) {
            if isExpanded {
                await space.loadChildren()
            }
        }
    }

    /// Whether the account has joined this room even though the room list does
    /// not hold it. The chat-list filter (MATRIX-67) narrows `rooms`, so a
    /// joined low-priority or filtered-out room is missing from it; without
    /// this check its space row would offer "Join".
    private var isJoinedOutsideRoomList: Bool {
        guard let room = try? appState.matrixClient?.client.getRoom(roomId: space.id) else { return false }
        if case .joined = room.membership() {
            return true
        }
        return false
    }

    /// Whether the SDK's space hierarchy item says the account has joined this
    /// room. Top-level rows come from the joined-spaces subscription, so for
    /// them this is the answer even when `getRoom` does not know the room.
    private var hierarchyStateIsJoined: Bool {
        if case .joined = space.spaceRoom.state {
            return true
        }
        return false
    }

    /// MATRIX-121: any one source saying "joined" means no "Join" link.
    private var isJoined: Bool {
        Models.SpaceRowMembership.isJoined(
            hierarchyStateIsJoined: hierarchyStateIsJoined,
            isInRoomList: appState.matrixClient?.rooms.contains(where: { $0.room.id() == space.id }) ?? false,
            clientReportsJoined: isJoinedOutsideRoomList
        )
    }

    var joinRoom: (() async throws -> Void)? {
        if appState.matrixClient != nil, !isJoined {
            return {
                Logger.viewCycle.error("Joining room: \(space.id)")
                guard let matrixClient = appState.matrixClient else { return }
                let room = try await matrixClient.client.joinRoomById(roomId: space.id)
                windowState.selectedScreen = .joinedRoom(timeline: LiveTimeline(room: LiveRoom(matrixRoom: room)))
            }
        }

        return nil
    }

    var joinedRoom: SidebarRoom? {
        return appState.matrixClient?.rooms.first(where: { $0.room.id() == space.id })
    }

    @ViewBuilder
    var roomRow: some View {
        if let joinedRoom {
            UI.RoomRow(
                title: space.spaceRoom.displayName,
                avatarUrl: space.spaceRoom.avatarUrl,
                roomInfo: joinedRoom.roomInfo,
                imageLoader: appState.matrixClient,
                joinRoom: nil
            )
            .contextMenu {
                RoomContextMenu(room: joinedRoom)
            }
        } else {
            UI.RoomRow(
                title: space.spaceRoom.displayName,
                avatarUrl: space.spaceRoom.avatarUrl,
                roomInfo: nil,
                imageLoader: appState.matrixClient,
                joinRoom: joinRoom
            )
        }
    }

    var body: some View {
        if space.spaceRoom.roomType == .space {
            spaceRow
        } else {
            roomRow
        }
    }
}

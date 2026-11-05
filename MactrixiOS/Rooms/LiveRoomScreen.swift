import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI

/// A room opened from the room list. It switches on the account's
/// membership, as the Mac `ChatView` does (MATRIX-104): a joined room shows
/// its live timeline, composer, and media (MATRIX-102); an invited room shows
/// Accept and Reject; the other cases show the Mac's notice.
///
/// The membership is the SDK's `Room.membership()`, the value the Mac reads.
/// The screen reads it again when the room's info changes (the SDK sends a
/// room info update on a membership change), when the room list hands over a
/// new SDK room, and when an invite call returns. So an accepted invite
/// opens the timeline in place.
///
/// A rejected invite closes the room through the shell's `closeRoom` action:
/// a pop on iPhone, a cleared selection on iPad. The room list service drops
/// the forgotten room from the list by itself.
struct LiveRoomScreen: View {
    @Environment(\.closeRoom) private var closeRoom

    let sidebarRoom: SidebarRoom
    let imageLoader: (any UI.ImageLoader)?

    /// Bumped when an invite call returns, so the body reads the membership
    /// again even before the room info update arrives.
    @State private var inviteCallsCompleted = 0

    var body: some View {
        RoomMembershipSwitch(membership: membership, title: sidebarRoom.title) {
            JoinedRoomScreen(sidebarRoom: sidebarRoom, imageLoader: imageLoader)
        } invited: {
            RoomInviteView(
                roomName: sidebarRoom.title,
                inviterName: RoomInviteDetails.inviterName(latestEvent: sidebarRoom.latestEvent),
                model: Self.inviteModel(for: sidebarRoom),
                onCompleted: inviteCompleted
            )
        }
    }

    /// The account's membership in the room.
    private var membership: Models.Membership {
        // Read for Observation only: a change to either re-runs the body.
        _ = sidebarRoom.roomInfo
        _ = inviteCallsCompleted
        switch sidebarRoom.room.membership() {
        case .joined:
            return .joined
        case .invited:
            return .invited
        case .left:
            return .left
        case .knocked:
            return .knocked
        case .banned:
            return .banned
        }
    }

    private func inviteCompleted(_ action: RoomInviteModel.Action) {
        inviteCallsCompleted += 1
        if action == .reject {
            closeRoom?()
        }
    }

    /// The Mac `ChatView.invitedRoom` calls: `join()` to accept, `leave()`
    /// then `forget()` to reject. The room is read at call time, so a newer
    /// SDK room from the room list is the one called.
    private static func inviteModel(for sidebarRoom: SidebarRoom) -> RoomInviteModel {
        RoomInviteModel(
            accept: {
                try await sidebarRoom.room.join()
            },
            reject: {
                try await sidebarRoom.room.leave()
                try await sidebarRoom.room.forget()
            }
        )
    }
}

/// A joined room: its live timeline, composer, and media (MATRIX-102).
///
/// It makes the room the way the Mac `MainView.onRoomSelected` does for a
/// room the room list service already delivered:
/// `LiveTimeline(room: LiveRoom(matrixRoom: sidebarRoom.room))`. The
/// `LiveRoom` is made here, once, on first appearance, because its init
/// subscribes to typing notices and syncs members. `TimelineScreen` then
/// makes the `LiveTimeline` over it, and sends the read receipts at the
/// points the Mac `ChatJoinedRoom` does: `.read` a second after the items
/// change while the scene is active, `.fullyRead` when the room closes.
///
/// Two seconds after the room shows, it is marked as recently visited, with
/// the call and delay of the Mac `ChatJoinedRoom`. Closing the room within
/// the delay cancels the sleep, and no call is made.
///
/// Both objects live in view state, so closing the room (a pop on iPhone, a
/// new selection on iPad) releases them, and with them the SDK timeline and
/// its listeners. This is how the Mac drops a room when its selected screen
/// changes.
private struct JoinedRoomScreen: View {
    @Environment(AppState.self) private var appState

    let sidebarRoom: SidebarRoom
    let imageLoader: (any UI.ImageLoader)?

    @State private var room: LiveRoom?

    var body: some View {
        Group {
            if let room {
                TimelineScreen(room: room, imageLoader: imageLoader)
            } else {
                Color(.systemBackground)
                    .navigationTitle(sidebarRoom.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onAppear {
            if room?.id != sidebarRoom.id {
                room = LiveRoom(matrixRoom: sidebarRoom.room)
            }
        }
        .task(priority: .background) {
            let roomID = sidebarRoom.id
            do {
                try await Task.sleep(for: .seconds(2))
                try await appState.matrixClient?.client.trackRecentlyVisitedRoom(room: roomID)
                Logger.roomList.debug("marked room as recently visited: \(roomID)")
            } catch is CancellationError {
                /* sleep cancelled */
            } catch {
                Logger.roomList.error("failed to mark room as recently visited: \(error)")
            }
        }
    }
}

import Core
import MatrixRustSDK
import OSLog
import SwiftUI
import UI

/// A room opened from the room list: its live timeline, composer, and media
/// (MATRIX-102).
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
struct LiveRoomScreen: View {
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

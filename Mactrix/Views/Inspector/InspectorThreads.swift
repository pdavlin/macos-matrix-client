import Core
import MatrixRustSDK
import Models
import SwiftUI
import UI

/// The Threads pane (MATRIX-200): the thread list of the open room, from the
/// SDK's `ThreadListService`.
///
/// A merged chat has no Threads pane (`InspectorScreen.shownContent`).
struct InspectorThreads: View {
    @Environment(WindowState.self) private var windowState

    private var room: LiveRoom? {
        guard case let .joinedRoom(timeline: timeline) = windowState.selectedScreen else {
            return nil
        }
        return timeline.room
    }

    var body: some View {
        if let room {
            RoomThreadList(room: room)
                // One list, and one service, for each room.
                .id(room.id)
        } else {
            Text("No room selected")
        }
    }
}

/// The thread list of one room. The task holds the SDK service and its
/// subscriptions while the pane shows this room; SwiftUI cancels it when the
/// room changes or the pane closes, and `LiveThreadList.run()` then drops
/// them.
private struct RoomThreadList: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let room: LiveRoom

    @State private var list: LiveThreadList?

    var body: some View {
        Group {
            if let list {
                ThreadListView(
                    entries: list.entries,
                    content: list.content,
                    pageRequestKey: list.finishedPageRequests,
                    imageLoader: appState.matrixClient,
                    onOpen: { windowState.focusThread(rootEventId: $0) },
                    onLoadMore: { await list.loadNextPage() },
                    onRetry: { await list.retry() }
                )
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let list = LiveThreadList(room: room.room)
            self.list = list
            await list.run()
        }
    }
}

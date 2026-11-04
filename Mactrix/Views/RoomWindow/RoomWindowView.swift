import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI

/// A single-room window (MATRIX-116, D-8): one room's timeline and composer,
/// no sidebar.
///
/// It shows the same `ChatView` the main window shows for a selected room,
/// with a `WindowState` of its own. That state holds the room's timeline as
/// `.joinedRoom`, so the inspector, the toolbar, and the menu commands that
/// read the key window's `WindowState` (the Edit-menu message target, for
/// example) act on this window when it is key.
///
/// What it shows comes from `RoomWindowPhase`, a pure function of the
/// session, the room list, and the room's membership. On relaunch, SwiftUI
/// restores the window with its `RoomWindowID`; the window waits for the
/// shared session restore before it looks up the room. A room the user
/// leaves, or a session that ends, shows an empty state.
struct RoomWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    let roomId: String

    /// This window's state. `singleRoomId` marks it as a room window for the
    /// menu commands.
    @State private var windowState: WindowState
    /// The last lookup that built no timeline: not found, left, or banned.
    @State private var lookupWithoutTimeline: RoomWindowRoomLookup = .notFound
    /// The client the timeline belongs to. A new client (a sign-in after a
    /// sign-out) gets a new timeline.
    @State private var timelineClientId: ObjectIdentifier?
    /// The room's name, kept for the title while the room is unavailable
    /// and on relaunch before the session is back.
    @SceneStorage("RoomWindow.title") private var lastKnownTitle = ""

    init(roomId: String) {
        self.roomId = roomId
        _windowState = State(initialValue: WindowState(singleRoomId: roomId))
    }

    // MARK: Inputs

    private var timeline: LiveTimeline? {
        guard case let .joinedRoom(timeline: timeline) = windowState.selectedScreen else { return nil }
        return timeline
    }

    /// A client whose auth failed counts as signed out: the main window
    /// tears it down and asks for a new sign-in (MATRIX-48).
    private var session: RoomWindowSession {
        if let client = appState.matrixClient {
            return client.authenticationFailed ? .signedOut : .signedIn
        }
        return appState.hasFinishedSessionRestore ? .signedOut : .restoring
    }

    private var roomListLoaded: Bool {
        appState.matrixClient?.roomListServiceState == .running
    }

    private var roomLookup: RoomWindowRoomLookup {
        guard let timeline else { return lookupWithoutTimeline }
        // Reading the observed room info makes a leave or a kick re-derive
        // the phase; the membership itself is not observable.
        _ = timeline.room.roomInfo
        return .found(timeline.room.room.membership().asModel)
    }

    private var phase: RoomWindowPhase {
        .resolve(session: session, roomListLoaded: roomListLoaded, room: roomLookup)
    }

    /// Re-runs the lookup when the client, the room list, or its load state
    /// changes.
    private var lookupKey: RoomLookupKey {
        RoomLookupKey(
            clientId: appState.matrixClient.map(ObjectIdentifier.init),
            roomCount: appState.matrixClient?.rooms.count ?? 0,
            roomListLoaded: roomListLoaded
        )
    }

    private var roomName: String? {
        timeline?.room.room.displayName()
    }

    private var windowTitle: String {
        if let roomName { return roomName }
        return lastKnownTitle.isEmpty ? String(localized: "Room") : lastKnownTitle
    }

    // MARK: Body

    var body: some View {
        @Bindable var windowState = windowState

        content
            .frame(minWidth: 360, minHeight: 300)
            .navigationTitle(windowTitle)
            .inspector(isPresented: $windowState.inspectorVisible) {
                InspectorScreen()
                    .environment(windowState)
            }
            // A relaunch can restore room windows and no main window, so
            // this window starts the restore too. It is shared, never run
            // twice.
            .task { await appState.restoreSavedSession() }
            .task(id: lookupKey) { resolveRoom() }
            .onChange(of: phase) { _, newPhase in
                if !newPhase.keepsTimeline { dropTimeline() }
            }
            .onChange(of: roomName) { _, newName in
                if let newName { lastKnownTitle = newName }
            }
            .onChange(of: windowState.selectedRoomId) { _, newRoomId in
                openElsewhere(newRoomId)
            }
            .modifier(ToolbarViewModifier())
            .environment(windowState)
            .focusedSceneValue(windowState)
            .background(WindowFrameAutosave(name: "RoomWindow \(roomId)"))
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .waitingForSession, .lookingUpRoom:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .showingRoom:
            if let timeline {
                ChatView(timeline: timeline).id(timeline.room.id)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case let .unavailable(reason):
            unavailable(reason)
        }
    }

    @ViewBuilder
    private func unavailable(_ reason: RoomWindowUnavailableReason) -> some View {
        switch reason {
        case .signedOut:
            ContentUnavailableView {
                Label("Signed Out", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Sign in from the main window to see this room again.")
            } actions: {
                Button("Show Main Window", action: showMainWindow)
                closeButton
            }
        case .notInRoomList:
            ContentUnavailableView {
                Label("Room Not Available", systemImage: "questionmark.bubble")
            } description: {
                Text("This room is not in your chat list.")
            } actions: {
                closeButton
            }
        case .left:
            ContentUnavailableView {
                Label("You Left This Room", systemImage: "rectangle.portrait.and.arrow.right")
            } description: {
                Text("If you join it again, it shows here again.")
            } actions: {
                closeButton
            }
        case .banned:
            ContentUnavailableView {
                Label("You Are Banned From This Room", systemImage: "nosign")
            } actions: {
                closeButton
            }
        }
    }

    private var closeButton: some View {
        Button("Close Window") { dismissWindow() }
    }

    // MARK: Behavior

    /// Looks up the room in the current client and builds its timeline.
    ///
    /// Same order as the main window (`MainView.onRoomSelected`): the room
    /// list's room first, then the client's store, which also holds rooms
    /// the sidebar filter hides.
    private func resolveRoom() {
        guard let client = appState.matrixClient, session == .signedIn else {
            lookupWithoutTimeline = .notFound
            dropTimeline()
            return
        }
        let clientId = ObjectIdentifier(client)
        if timeline != nil, timelineClientId == clientId { return }

        let matrixRoom: MatrixRustSDK.Room?
        if let sidebarRoom = client.rooms.first(where: { $0.id == roomId }) {
            matrixRoom = sidebarRoom.room
        } else {
            do {
                matrixRoom = try client.client.getRoom(roomId: roomId)
            } catch {
                Logger.viewCycle.error("room window: failed to get room \(roomId): \(error)")
                matrixRoom = nil
            }
        }

        guard let matrixRoom else {
            lookupWithoutTimeline = .notFound
            dropTimeline()
            return
        }

        let lookup = RoomWindowRoomLookup.found(matrixRoom.membership().asModel)
        guard RoomWindowPhase.resolve(session: .signedIn, roomListLoaded: roomListLoaded, room: lookup).keepsTimeline else {
            lookupWithoutTimeline = lookup
            dropTimeline()
            return
        }

        windowState.selectedScreen = .joinedRoom(timeline: LiveTimeline(room: LiveRoom(matrixRoom: matrixRoom)))
        timelineClientId = clientId
    }

    /// Lets go of the timeline, keeping what the lookup last saw so the
    /// phase does not change with it.
    private func dropTimeline() {
        guard timeline != nil else { return }
        if appState.matrixClient != nil {
            lookupWithoutTimeline = roomLookup
        }
        windowState.selectedScreen = .none
        windowState.inspectorVisible = false
        timelineClientId = nil
    }

    /// An action in this window selected another room, for example "Send
    /// Message" in a member's inspector. This window keeps its room; the
    /// other room opens in its own window.
    private func openElsewhere(_ newRoomId: String?) {
        guard newRoomId != roomId else { return }
        windowState.selectedRoomId = roomId
        if let newRoomId {
            openWindow(value: RoomWindowID(roomId: newRoomId))
        }
    }

    private func showMainWindow() {
        if let mainWindow = NSApp.frontmostMainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}

private struct RoomLookupKey: Equatable {
    let clientId: ObjectIdentifier?
    let roomCount: Int
    let roomListLoaded: Bool
}

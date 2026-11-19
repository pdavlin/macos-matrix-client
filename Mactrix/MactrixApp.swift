import Core
import Models
import OSLog
import SwiftUI
import Utils

@main
struct MactrixApp: App {
    @State var appState = AppState()
    @FocusedValue(WindowState.self) private var windowState: WindowState?
    /// The Matrix link click that waits for the key window (MATRIX-203).
    @State private var linkInbox = MatrixLinkInbox.shared

    init() {
        // MATRIX-122: macOS starts apps at 256 open files, which the SDK's
        // SQLite pools exhausted. Raise it before any store opens.
        if let limit = FileDescriptorLimit.raiseSoftLimit() {
            Logger.matrixClient.info("open-file soft limit: \(limit.before) -> \(limit.after)")
        }
        // MATRIX-166 follow-up: tooltips show after 400 ms. Registered here,
        // before AppKit makes its tooltip manager and before any window shows.
        ToolTipDelay.register()
        // MATRIX-201, MATRIX-203: a plain click on a link in a message body
        // opens a Matrix link in the app and an X or Bluesky post in a
        // popover.
        BodyLinkRouter.install()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView()
        }
        .windowToolbarStyle(.automatic)
        .environment(appState)
        .commands {
            AppCommands()
            GoCommands()
            MessageCommands()
            CustomEmojiCommands(appState: appState)
        }
        // Keyed on the window, not only on whether one is key: moving from a
        // room window to a main window hands that window a waiting
        // notification (MATRIX-116).
        .onChange(of: windowState.map(ObjectIdentifier.init), focusNotification)
        .onChange(of: appState.matrixClient?.notifications.selectedRoomId == nil, focusNotification)
        // MATRIX-203: a Matrix link click opens in the key window; one that a
        // room window cannot open waits for a main window.
        .onChange(of: windowState.map(ObjectIdentifier.init), openMatrixLink)
        .onChange(of: linkInbox.pending?.id, openMatrixLink)

        // MATRIX-116 (D-8): one window per room, opened from the room's
        // context menu and with ⌥-Return in ⌘K. Opening a room that has a
        // window brings that window forward. SwiftUI restores these windows,
        // with their room, on relaunch.
        WindowGroup("Room", id: "room", for: RoomWindowID.self) { $roomWindow in
            if let roomWindow {
                RoomWindowView(roomId: roomWindow.roomId)
                    .id(roomWindow.roomId)
            } else {
                ContentUnavailableView("No room", systemImage: "message.fill")
            }
        }
        .defaultSize(width: 560, height: 720)
        .commandsRemoved()
        .environment(appState)

        Settings {
            SettingsView()
        }
        .environment(appState)
    }

    /// Opens the waiting Matrix link click in the key window (MATRIX-203).
    /// A room window opens only a link to its own room; for any other link
    /// a main window comes forward, and this method runs again when it
    /// becomes key.
    func openMatrixLink() {
        guard let windowState, let client = appState.matrixClient, let request = linkInbox.pending else { return }
        guard MatrixLinkPlan.opens(request.link, inWindowOf: windowState.singleRoomId) else {
            NSApp.frontmostMainWindow?.makeKeyAndOrderFront(nil)
            return
        }
        linkInbox.pending = nil
        Task {
            await client.openMatrixLink(request.link, url: request.url, in: windowState)
        }
    }

    func focusNotification() {
        guard let windowState, let client = appState.matrixClient,
              let notificationRoomId = client.notifications.selectedRoomId else { return }

        // A room window shows only its own room (MATRIX-116). A notification
        // for another room goes to a main window: bring one forward, and
        // this method runs again when it becomes key. A main window shows a
        // member room's merged chat (MATRIX-141).
        let focus = MergedChatSelection.notificationFocus(
            roomId: notificationRoomId,
            singleRoomId: windowState.singleRoomId,
            document: client.mergedChats?.document ?? MergedChatDocument()
        )
        switch focus {
        case .alreadyShown:
            // MATRIX-188: the chat is open; its composer takes the focus.
            windowState.requestComposerFocus(from: .notification)
            client.notifications.selectedRoomId = nil
        case .bringMainWindowForward:
            NSApp.frontmostMainWindow?.makeKeyAndOrderFront(nil)
        case let .select(selection):
            windowState.open(selection, from: .notification)
            client.notifications.selectedRoomId = nil
        }
    }
}

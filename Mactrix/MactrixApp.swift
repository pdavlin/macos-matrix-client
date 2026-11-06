import Core
import Models
import OSLog
import SwiftUI
import Utils

@main
struct MactrixApp: App {
    @State var appState = AppState()
    @FocusedValue(WindowState.self) private var windowState: WindowState?

    init() {
        // MATRIX-122: macOS starts apps at 256 open files, which the SDK's
        // SQLite pools exhausted. Raise it before any store opens.
        if let limit = FileDescriptorLimit.raiseSoftLimit() {
            Logger.matrixClient.info("open-file soft limit: \(limit.before) -> \(limit.after)")
        }
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
        }
        // Keyed on the window, not only on whether one is key: moving from a
        // room window to a main window hands that window a waiting
        // notification (MATRIX-116).
        .onChange(of: windowState.map(ObjectIdentifier.init), focusNotification)
        .onChange(of: appState.matrixClient?.notifications.selectedRoomId == nil, focusNotification)

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

    func focusNotification() {
        guard let windowState, let notificationRoomId = appState.matrixClient?.notifications.selectedRoomId else { return }

        // A room window shows only its own room (MATRIX-116). A notification
        // for another room goes to a main window: bring one forward, and
        // this method runs again when it becomes key.
        if let singleRoomId = windowState.singleRoomId {
            if singleRoomId == notificationRoomId {
                appState.matrixClient?.notifications.selectedRoomId = nil
            } else {
                NSApp.frontmostMainWindow?.makeKeyAndOrderFront(nil)
            }
            return
        }

        windowState.selectedRoomId = notificationRoomId
        appState.matrixClient?.notifications.selectedRoomId = nil
    }
}

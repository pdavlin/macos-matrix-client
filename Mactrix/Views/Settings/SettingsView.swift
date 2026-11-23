import Core
import MatrixRustSDK
import Models
import SwiftUI
import UI

struct SettingsView: View {
    /// MATRIX-215: whether macOS blocks notifications for Mactrix.
    private let notificationPermission = NotificationPermissionModel.shared

    var body: some View {
        TabView {
            Tab("Account", systemImage: "person") {
                AccountSettingsView()
            }
            Tab("Appearance", systemImage: "eye") {
                AppearanceSettingsView()
            }
            // MATRIX-222.
            Tab("Inbox", systemImage: "tray") {
                InboxSettingsView()
            }
            Tab("Composer", systemImage: "square.and.pencil") {
                ComposerSettingsView()
            }
            Tab("Notifications", systemImage: "bell.badge") {
                NotificationSettingsView(isBlockedBySystem: notificationPermission.permission == .blocked)
                    .task { await notificationPermission.refresh() }
                    // Back from System Settings: show the new permission.
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                        Task { await notificationPermission.refresh() }
                    }
            }
            Tab("Sessions", systemImage: "desktopcomputer.and.macbook") {
                SessionsSettingsView()
            }
        }
        .scenePadding()
        .frame(maxWidth: 450, minHeight: 200)
    }
}

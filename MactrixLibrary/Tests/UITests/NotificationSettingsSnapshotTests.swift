import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshots for Settings > Notifications (MATRIX-117, Dock badge switch
/// MATRIX-119).
///
/// Each test reads the settings from its own `UserDefaults` suite, so the
/// snapshot never depends on what the test host's standard defaults hold, and
/// parallel tests never share state. The 450-point width matches the frame
/// `SettingsView` gives its tabs.
@MainActor
struct NotificationSettingsSnapshotTests {
    private func isolatedDefaults(
        suite: String,
        showsNotifications: Bool?,
        playsSound: Bool?,
        showsDockBadge: Bool? = nil
    ) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        if let showsNotifications {
            defaults.set(showsNotifications, forKey: NotificationPreferences.showNotificationsStorageKey)
        }
        if let playsSound {
            defaults.set(playsSound, forKey: NotificationPreferences.playNotificationSoundStorageKey)
        }
        if let showsDockBadge {
            defaults.set(showsDockBadge, forKey: NotificationPreferences.showDockBadgeStorageKey)
        }
        return defaults
    }

    private func assertPinnedSnapshot(
        of view: some View,
        testName: String = #function
    ) {
        let controller = NSHostingController(rootView: view.frame(width: 450).padding())
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance so the snapshot does not flip with light/dark mode.
        controller.view.appearance = NSAppearance(named: .aqua)

        assertSnapshot(of: controller, as: .scaledImage, testName: testName)
    }

    /// A user who never opened the tab sees every switch on.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func defaultsAllOn() throws {
        let defaults = try isolatedDefaults(
            suite: "NotificationSettingsSnapshotTests.default",
            showsNotifications: nil,
            playsSound: nil
        )
        assertPinnedSnapshot(of: NotificationSettingsView(store: defaults))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func soundOff() throws {
        let defaults = try isolatedDefaults(
            suite: "NotificationSettingsSnapshotTests.soundOff",
            showsNotifications: true,
            playsSound: false
        )
        assertPinnedSnapshot(of: NotificationSettingsView(store: defaults))
    }

    /// Notifications off: the sound switch shows as disabled.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func notificationsOff() throws {
        let defaults = try isolatedDefaults(
            suite: "NotificationSettingsSnapshotTests.notificationsOff",
            showsNotifications: false,
            playsSound: true
        )
        assertPinnedSnapshot(of: NotificationSettingsView(store: defaults))
    }

    /// The Dock badge switch is independent of the notification switches.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func dockBadgeOff() throws {
        let defaults = try isolatedDefaults(
            suite: "NotificationSettingsSnapshotTests.dockBadgeOff",
            showsNotifications: true,
            playsSound: true,
            showsDockBadge: false
        )
        assertPinnedSnapshot(of: NotificationSettingsView(store: defaults))
    }
}

import Models
import SwiftUI

/// Settings > Notifications: global switches for system notifications and
/// their sound (MATRIX-117).
///
/// Each switch is stored with `@AppStorage` under its
/// `NotificationPreferences` storage key. `MatrixNotifications` reads the same
/// keys for each notification, so a change applies at once. The rule that
/// decides whether a notification posts lives in `NotificationDecision`; this
/// view only edits the settings. Per-room mute and the MATRIX-77 label mute
/// are not here and still apply first.
///
/// The view lives in the UI library rather than the app target so its
/// snapshot test exercises the shipped view.
public struct NotificationSettingsView: View {
    @AppStorage private var showsNotifications: Bool
    @AppStorage private var playsSound: Bool

    /// - Parameter store: the defaults store to read and write. `nil` uses
    ///   `UserDefaults.standard`; tests pass an isolated suite.
    public init(store: UserDefaults? = nil) {
        _showsNotifications = AppStorage(
            wrappedValue: NotificationPreferences.defaultShowsNotifications,
            NotificationPreferences.showNotificationsStorageKey,
            store: store
        )
        _playsSound = AppStorage(
            wrappedValue: NotificationPreferences.defaultPlaysSound,
            NotificationPreferences.playNotificationSoundStorageKey,
            store: store
        )
    }

    public var body: some View {
        Form {
            Toggle("Show notifications", isOn: $showsNotifications)
            Toggle("Play sound", isOn: $playsSound)
                // No notification posts, so there is no sound to play.
                .disabled(!showsNotifications)
        }
    }
}

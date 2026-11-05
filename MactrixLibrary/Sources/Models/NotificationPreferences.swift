import Foundation

/// The user's global notification settings (MATRIX-117, Settings >
/// Notifications).
///
/// Each value is stored with `@AppStorage` under its `...StorageKey`. The
/// keys are persisted user settings: do not rename them. A key that was never
/// written reads as its default, so a fresh install shows notifications and
/// plays a sound.
///
/// Per-room mute (a push rule) and the MATRIX-77 label mute are not settings
/// here: they apply before these values, see
/// `NotificationDecision.decide(isMutedByLabel:settings:)`.
public struct NotificationPreferences: Equatable, Sendable {
    /// Post a system notification for a new message.
    public var showsNotifications: Bool
    /// Play the default notification sound with each notification.
    public var playsSound: Bool

    /// `UserDefaults` key of `showsNotifications`. Same naming style as
    /// `ComposerKeyDecision.SendMode.storageKey`.
    public static let showNotificationsStorageKey = "showNotifications"
    /// `UserDefaults` key of `playsSound`.
    public static let playNotificationSoundStorageKey = "playNotificationSound"

    /// Value of `showsNotifications` when the user never changed it.
    public static let defaultShowsNotifications = true
    /// Value of `playsSound` when the user never changed it.
    public static let defaultPlaysSound = true

    public init(
        showsNotifications: Bool = NotificationPreferences.defaultShowsNotifications,
        playsSound: Bool = NotificationPreferences.defaultPlaysSound
    ) {
        self.showsNotifications = showsNotifications
        self.playsSound = playsSound
    }

    /// Reads the current settings from `defaults`. A missing or non-Bool
    /// value reads as its default.
    ///
    /// Read this at the moment a notification is due, not once at launch, so
    /// a change in Settings applies at once.
    public init(defaults: UserDefaults) {
        let storedShow: Bool? = defaults.object(forKey: Self.showNotificationsStorageKey) as? Bool
        let storedSound: Bool? = defaults.object(forKey: Self.playNotificationSoundStorageKey) as? Bool
        self.init(
            showsNotifications: storedShow ?? Self.defaultShowsNotifications,
            playsSound: storedSound ?? Self.defaultPlaysSound
        )
    }
}

/// Whether a notification from the sync listener posts, and with which sound
/// (MATRIX-117).
///
/// Pure decision logic, kept out of `MatrixNotifications` so the rule is unit
/// tested without `UNUserNotificationCenter`.
public enum NotificationDecision: Equatable, Sendable {
    /// Post a `UNNotificationRequest`. `playsSound` decides whether the
    /// content carries the default sound.
    case post(playsSound: Bool)
    /// Post nothing.
    case suppress(SuppressReason)

    /// Why a notification does not post. Used for the debug log.
    public enum SuppressReason: Equatable, Sendable {
        /// Every label that holds the room is muted (MATRIX-77).
        case mutedByLabel
        /// The user turned off Settings > Notifications > Show notifications.
        case notificationsOff
    }

    /// Decides what to do with one notification.
    ///
    /// The label mute applies first, the same as before MATRIX-117. Per-room
    /// mute is a push rule: it applies upstream of this function, and this
    /// function does not change it.
    ///
    /// - Parameters:
    ///   - isMutedByLabel: the room is in `MatrixNotifications.labelMutedRoomIds`.
    ///   - settings: the user's settings, read when the notification is due.
    public static func decide(isMutedByLabel: Bool, settings: NotificationPreferences) -> NotificationDecision {
        if isMutedByLabel {
            return .suppress(.mutedByLabel)
        }
        guard settings.showsNotifications else {
            return .suppress(.notificationsOff)
        }
        return .post(playsSound: settings.playsSound)
    }
}

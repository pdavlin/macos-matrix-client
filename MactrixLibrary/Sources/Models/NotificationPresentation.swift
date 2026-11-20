import Foundation

/// Whether a notification shows while Mactrix is running (MATRIX-215).
///
/// macOS asks the notification center's delegate
/// (`userNotificationCenter(_:willPresent:)`) what to show when a
/// notification arrives while the app is active. Without an answer macOS
/// shows nothing. This is the pure rule behind that answer, kept out of
/// `MatrixNotifications` so it is unit tested without
/// `UNUserNotificationCenter`.
public enum NotificationPresentation {
    /// Decides whether a notification shows as a banner, in Notification
    /// Center, and with its sound, or does not show at all.
    ///
    /// A message notification does not show when the app is active and the
    /// key window shows its chat: the message is already on screen. The key
    /// window shows the chat when it selects the room, or the merged chat
    /// that holds the room (MATRIX-141). Every other notification shows.
    ///
    /// A snooze end or a reminder (MATRIX-207) always shows: the user asked
    /// for it, and a notification that does not show is not kept.
    ///
    /// - Parameters:
    ///   - roomId: the notification's room, or nil when it has none.
    ///   - isReminder: the notification is a snooze end or a reminder, not a
    ///     message.
    ///   - appIsActive: Mactrix is the active app.
    ///   - keyWindowSelection: what the key window selects, or nil when no
    ///     Mactrix window is key or it selects no chat.
    ///   - document: the account's merged chats.
    /// - Returns: true to show the notification, false to drop it.
    public static func shows(
        roomId: String?,
        isReminder: Bool,
        appIsActive: Bool,
        keyWindowSelection: ChatSelection?,
        document: MergedChatDocument
    ) -> Bool {
        guard !isReminder, appIsActive, let roomId, let keyWindowSelection else { return true }
        if keyWindowSelection == .room(roomId) {
            return false
        }
        if let merge = document.merge(containing: roomId), keyWindowSelection == .merged(merge.id) {
            return false
        }
        return true
    }
}

/// Whether macOS lets Mactrix post notifications (MATRIX-215), as Settings >
/// Notifications shows it.
public enum NotificationPermission: Equatable, Sendable {
    /// Not known yet: the permission was not read, or Mactrix has not asked.
    case unknown
    /// macOS shows Mactrix's notifications.
    case allowed
    /// macOS refuses Mactrix's notifications: the user turned them off in
    /// System Settings, or the authorization request failed.
    case blocked

    /// System Settings > Notifications. Settings > Notifications opens it
    /// when macOS blocks notifications.
    public static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
}

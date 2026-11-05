import Foundation
import Models
import Testing

/// MATRIX-117: the global notification settings and the rule that decides
/// whether a notification posts, and with which sound.
struct NotificationDecisionTests {
    private func isolatedDefaults(suite: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: Decision

    @Test func defaultsPostWithSound() {
        let decision = NotificationDecision.decide(isMutedByLabel: false, settings: NotificationPreferences())
        #expect(decision == .post(playsSound: true))
    }

    @Test func soundOffPostsSilently() {
        let settings = NotificationPreferences(showsNotifications: true, playsSound: false)
        #expect(NotificationDecision.decide(isMutedByLabel: false, settings: settings) == .post(playsSound: false))
    }

    @Test(arguments: [true, false])
    func notificationsOffSuppressesWhateverTheSound(playsSound: Bool) {
        let settings = NotificationPreferences(showsNotifications: false, playsSound: playsSound)
        #expect(NotificationDecision.decide(isMutedByLabel: false, settings: settings) == .suppress(.notificationsOff))
    }

    /// The MATRIX-77 label mute applies first, whatever the settings hold.
    @Test(arguments: [true, false], [true, false])
    func labelMuteAppliesFirst(showsNotifications: Bool, playsSound: Bool) {
        let settings = NotificationPreferences(showsNotifications: showsNotifications, playsSound: playsSound)
        #expect(NotificationDecision.decide(isMutedByLabel: true, settings: settings) == .suppress(.mutedByLabel))
    }

    // MARK: Reading the store

    @Test func emptyStoreReadsAsDefaults() throws {
        let defaults = try isolatedDefaults(suite: "NotificationDecisionTests.empty")
        let settings = NotificationPreferences(defaults: defaults)
        #expect(settings == NotificationPreferences(showsNotifications: true, playsSound: true))
    }

    @Test func storedValuesAreReadOnEachRead() throws {
        let defaults = try isolatedDefaults(suite: "NotificationDecisionTests.stored")
        defaults.set(false, forKey: NotificationPreferences.showNotificationsStorageKey)
        defaults.set(false, forKey: NotificationPreferences.playNotificationSoundStorageKey)
        let first = NotificationPreferences(defaults: defaults)
        #expect(first == NotificationPreferences(showsNotifications: false, playsSound: false))

        // A later write is seen by the next read: no relaunch needed.
        defaults.set(true, forKey: NotificationPreferences.showNotificationsStorageKey)
        let second = NotificationPreferences(defaults: defaults)
        #expect(second == NotificationPreferences(showsNotifications: true, playsSound: false))
    }

    @Test func nonBoolValueReadsAsDefault() throws {
        let defaults = try isolatedDefaults(suite: "NotificationDecisionTests.nonBool")
        defaults.set("off", forKey: NotificationPreferences.showNotificationsStorageKey)
        #expect(NotificationPreferences(defaults: defaults).showsNotifications)
    }

    /// Stored user settings: renaming a key silently resets every user's
    /// choice.
    @Test func storageContractIsStable() {
        #expect(NotificationPreferences.showNotificationsStorageKey == "showNotifications")
        #expect(NotificationPreferences.playNotificationSoundStorageKey == "playNotificationSound")
        #expect(NotificationPreferences.defaultShowsNotifications)
        #expect(NotificationPreferences.defaultPlaysSound)
    }
}

import Foundation
import Models
import Testing

/// MATRIX-119: the Dock badge counts chats with unread activity, not
/// messages, and skips muted rooms.
struct DockBadgeTests {
    // MARK: Counting one chat

    @Test func readChatDoesNotCount() {
        let chat = UnreadChatState(roomId: "!a")
        #expect(!DockBadge.counts(chat, isMutedByLabel: false))
    }

    @Test(arguments: [false, true])
    func unreadNotificationsCount(isDirect: Bool) {
        let chat = UnreadChatState(roomId: "!a", numUnreadNotifications: 1, numUnreadMessages: 1, isDirect: isDirect)
        #expect(DockBadge.counts(chat, isMutedByLabel: false))
    }

    /// A DM counts on unread messages alone, even when the push rules say
    /// they do not notify.
    @Test func directChatCountsOnUnreadMessages() {
        let chat = UnreadChatState(roomId: "!a", numUnreadMessages: 3, isDirect: true)
        #expect(DockBadge.counts(chat, isMutedByLabel: false))
    }

    /// A group with messages that do not notify (for example a mentions-only
    /// room) does not count.
    @Test func groupDoesNotCountOnUnreadMessagesAlone() {
        let chat = UnreadChatState(roomId: "!a", numUnreadMessages: 3, isDirect: false)
        #expect(!DockBadge.counts(chat, isMutedByLabel: false))
    }

    @Test(arguments: [false, true])
    func markedUnreadCounts(isDirect: Bool) {
        let chat = UnreadChatState(roomId: "!a", isDirect: isDirect, isMarkedUnread: true)
        #expect(DockBadge.counts(chat, isMutedByLabel: false))
    }

    /// Mute wins over every unread signal.
    @Test(arguments: [false, true])
    func mutedRoomNeverCounts(isDirect: Bool) {
        let chat = UnreadChatState(
            roomId: "!a",
            numUnreadNotifications: 5,
            numUnreadMessages: 5,
            isDirect: isDirect,
            isMarkedUnread: true,
            isMuted: true
        )
        #expect(!DockBadge.counts(chat, isMutedByLabel: false))
    }

    @Test(arguments: [false, true])
    func labelMutedRoomNeverCounts(isDirect: Bool) {
        let chat = UnreadChatState(
            roomId: "!a",
            numUnreadNotifications: 5,
            numUnreadMessages: 5,
            isDirect: isDirect,
            isMarkedUnread: true
        )
        #expect(!DockBadge.counts(chat, isMutedByLabel: true))
    }

    // MARK: Counting all chats

    @Test func countsChatsNotMessages() {
        let chats = [
            UnreadChatState(roomId: "!dm", numUnreadNotifications: 12, numUnreadMessages: 12, isDirect: true),
            UnreadChatState(roomId: "!group", numUnreadNotifications: 40, numUnreadMessages: 40),
            UnreadChatState(roomId: "!marked", isMarkedUnread: true),
            UnreadChatState(roomId: "!read"),
            UnreadChatState(roomId: "!muted", numUnreadNotifications: 9, isMuted: true),
            UnreadChatState(roomId: "!labelMuted", numUnreadNotifications: 9),
            UnreadChatState(roomId: "!quietGroup", numUnreadMessages: 9),
        ]
        #expect(DockBadge.unreadChatCount(chats, labelMutedRoomIds: ["!labelMuted"]) == 3)
    }

    @Test func noChatsCountsZero() {
        #expect(DockBadge.unreadChatCount([UnreadChatState](), labelMutedRoomIds: []) == 0)
    }

    /// A label-muted ID with no matching chat changes nothing.
    @Test func unknownLabelMutedRoomIsIgnored() {
        let chats = [UnreadChatState(roomId: "!a", numUnreadNotifications: 1)]
        #expect(DockBadge.unreadChatCount(chats, labelMutedRoomIds: ["!other"]) == 1)
    }

    // MARK: Label

    @Test func zeroShowsNoBadge() {
        #expect(DockBadge.label(unreadChatCount: 0, isEnabled: true) == nil)
    }

    @Test func countShowsAsDigits() {
        #expect(DockBadge.label(unreadChatCount: 1, isEnabled: true) == "1")
        #expect(DockBadge.label(unreadChatCount: 142, isEnabled: true) == "142")
    }

    @Test func switchedOffShowsNoBadge() {
        #expect(DockBadge.label(unreadChatCount: 7, isEnabled: false) == nil)
    }

    // MARK: Setting

    @Test func dockBadgeIsOnByDefault() throws {
        let suite = "DockBadgeTests.default"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        #expect(NotificationPreferences(defaults: defaults).showsDockBadge)
    }

    @Test func dockBadgeSwitchIsRead() throws {
        let suite = "DockBadgeTests.off"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: NotificationPreferences.showDockBadgeStorageKey)
        let settings = NotificationPreferences(defaults: defaults)
        #expect(!settings.showsDockBadge)
        // The other two switches keep their defaults.
        #expect(settings.showsNotifications)
        #expect(settings.playsSound)
    }

    /// Stored user setting: renaming the key silently resets every user's
    /// choice.
    @Test func storageContractIsStable() {
        #expect(NotificationPreferences.showDockBadgeStorageKey == "showDockBadge")
        #expect(NotificationPreferences.defaultShowsDockBadge)
    }
}

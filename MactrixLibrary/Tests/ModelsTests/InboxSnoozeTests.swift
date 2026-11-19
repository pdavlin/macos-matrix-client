import Foundation
@testable import Models
import Testing

/// MATRIX-207: Snooze and Remind me later on the inbox-state model: the
/// actions, the due times, the remind-if-no-reply rule, and the launch-time
/// resolution.
struct InboxSnoozeTests {
    /// Wednesday 2026-11-18 10:30 UTC.
    private static let wednesday = Date(timeIntervalSince1970: 1_794_997_800)
    private static let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"], defaultRoom: "!s2")
    private static let merges = MergedChatDocument(merges: [seth])

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func time(_ minutes: Double) -> Date {
        Self.wednesday.addingTimeInterval(minutes * 60)
    }

    private func components(_ date: Date?) -> DateComponents? {
        date.map { Self.utc.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: $0) }
    }

    // MARK: Actions

    @Test
    func snoozeHidesTheChatAndEndsAnArchive() {
        var document = InboxStateDocument()
        document.archive(["!a"], at: time(0))
        document.remind(["!a"], at: time(30), setAt: time(0))
        document.snooze(["!a"], until: time(60), at: time(1))
        #expect(document.placement(of: "!a") == .snoozed)
        #expect(document.state(of: "!a").archivedAt == nil)
        #expect(document.state(of: "!a").remindAt == time(30))
        #expect(document.hiddenRoomIds(merges: Self.merges) == ["!a"])
        #expect(ChatListFilter.snoozed.inboxPlacement == .snoozed)
    }

    @Test
    func unsnoozeAndCancelReminderRemoveTheEntry() {
        var document = InboxStateDocument()
        document.snooze(["!a"], until: time(60), at: time(0))
        document.remind(["!a"], at: time(30), setAt: time(0))
        document.unsnooze(["!a"])
        #expect(document.placement(of: "!a") == .inbox)
        document.cancelReminder(["!a"])
        #expect(document.rooms.isEmpty)
    }

    @Test
    func reminderKeepsTheChatInTheInbox() {
        var document = InboxStateDocument()
        document.remind(["!a"], at: time(30), setAt: time(0))
        #expect(document.placement(of: "!a") == .inbox)
        #expect(document.hiddenRoomIds(merges: Self.merges).isEmpty)
    }

    // MARK: Due times

    @Test
    func nextDueDateIsTheEarliestSnoozeEndOrReminder() {
        var document = InboxStateDocument()
        #expect(document.nextDueDate == nil)
        document.snooze(["!a"], until: time(60), at: time(0))
        document.remind(["!b"], at: time(30), setAt: time(0))
        #expect(document.nextDueDate == time(30))
    }

    @Test
    func dueChatsHoldOnlyWhatCameDue() {
        var document = InboxStateDocument()
        document.snooze(["!a"], until: time(10), at: time(0))
        document.remind(["!b"], at: time(20), setAt: time(0))
        document.snooze(["!c"], until: time(90), at: time(0))
        let due = document.dueChats(at: time(20), merges: Self.merges)
        #expect(due.map(\.id) == ["!a", "!b"])
        #expect(due[0].snoozeEnded && !due[0].reminderFired)
        #expect(due[1].reminderFired && !due[1].snoozeEnded)
    }

    @Test
    func launchResolvesEveryItemThatCameDueWhileClosed() {
        var document = InboxStateDocument()
        document.snooze(["!a"], until: time(10), at: time(0))
        document.remind(["!b"], at: time(20), setAt: time(0))
        document.snooze(["!c"], until: time(24 * 60), at: time(0))
        let launch = time(2 * 24 * 60)
        let due = document.dueChats(at: launch, merges: Self.merges)
        #expect(due.map(\.id) == ["!a", "!b", "!c"])
        document.resolve(due, at: launch)
        #expect(document.rooms.isEmpty)
        #expect(document.nextDueDate == nil)
    }

    @Test
    func mergedChatComesDueAsOneChat() {
        var document = InboxStateDocument()
        document.snooze(["!s1", "!s2"], until: time(10), at: time(0))
        let due = document.dueChats(at: time(10), merges: Self.merges)
        let expected = InboxDueChat(id: "m-seth", roomIds: ["!s1", "!s2"], mergedChatName: "Seth", defaultRoomId: "!s2", snoozeEnded: true)
        #expect(due == [expected])
        document.resolve(due, at: time(10))
        #expect(document.placement(of: "!s1", merges: Self.merges) == .inbox)
    }

    @Test
    func resolveKeepsANewerSnoozeAndADueReminderUnarchives() {
        var document = InboxStateDocument()
        document.snooze(["!a"], until: time(10), at: time(0))
        document.archive(["!b"], at: time(0))
        document.remind(["!b"], at: time(10), setAt: time(0))
        let due = document.dueChats(at: time(10), merges: Self.merges)
        // Another device snoozed "!a" again before this write.
        document.snooze(["!a"], until: time(120), at: time(5))
        document.resolve(due, at: time(10))
        #expect(document.state(of: "!a").snoozedUntil == time(120))
        #expect(document.placement(of: "!b") == .inbox)
        #expect(document.state(of: "!b").remindAt == nil)
    }

    @Test
    func notificationText() {
        let reminder = InboxDueChat(id: "!a", roomIds: ["!a"], defaultRoomId: "!a", reminderFired: true)
        #expect(reminder.notification(chatName: "Alice").title == "Reminder: Alice")
        let snooze = InboxDueChat(id: "!a", roomIds: ["!a"], defaultRoomId: "!a", snoozeEnded: true)
        #expect(snooze.notification(chatName: "Alice") == (title: "Alice", body: "Snooze ended."))
    }

    // MARK: Remind if no reply

    @Test
    func replyAfterTheReminderWasSetDropsItSilently() {
        var document = InboxStateDocument()
        document.remind(["!a"], at: time(60), setAt: time(0))
        document.applyActivity(InboxActivity(timestamp: time(5), isOwn: false), in: "!a", merges: Self.merges)
        #expect(document.dueChats(at: time(60), merges: Self.merges).isEmpty)
    }

    @Test
    func ownMessageOrOlderMessageKeepsTheReminder() {
        var document = InboxStateDocument()
        document.remind(["!a"], at: time(60), setAt: time(0))
        document.applyActivity(InboxActivity(timestamp: time(5), isOwn: true), in: "!a", merges: Self.merges)
        document.applyActivity(InboxActivity(timestamp: time(-5), isOwn: false), in: "!a", merges: Self.merges)
        #expect(document.dueChats(at: time(60), merges: Self.merges).map(\.id) == ["!a"])
    }

    @Test
    func messageFromAnotherPersonEndsASnoozeEarly() {
        var document = InboxStateDocument()
        document.snooze(["!s1", "!s2"], until: time(600), at: time(0))
        document.applyActivity(InboxActivity(timestamp: time(5), isOwn: false), in: "!s1", merges: Self.merges)
        #expect(document.placement(of: "!s2", merges: Self.merges) == .inbox)
        #expect(document.nextDueDate == nil)
    }

    // MARK: Time choices

    @Test
    func oneHourIsAnHourFromNow() {
        #expect(InboxTimeChoice.oneHour.date(now: Self.wednesday, calendar: Self.utc) == time(60))
    }

    @Test
    func thisEveningIsSixTodayAndGoneAfterSix() {
        let evening = components(InboxTimeChoice.thisEvening.date(now: Self.wednesday, calendar: Self.utc))
        #expect(evening?.day == 18)
        #expect(evening?.hour == 18)
        let late = Self.utc.date(bySettingHour: 18, minute: 30, second: 0, of: Self.wednesday) ?? Self.wednesday
        #expect(InboxTimeChoice.thisEvening.date(now: late, calendar: Self.utc) == nil)
    }

    @Test
    func tomorrowIsNineTheNextDay() {
        let tomorrow = components(InboxTimeChoice.tomorrow.date(now: Self.wednesday, calendar: Self.utc))
        #expect(tomorrow?.day == 19)
        #expect(tomorrow?.hour == 9)
        #expect(tomorrow?.minute == 0)
    }

    @Test
    func nextWeekIsTheNextMondayAtNine() {
        let fromWednesday = components(InboxTimeChoice.nextWeek.date(now: Self.wednesday, calendar: Self.utc))
        #expect(fromWednesday?.weekday == 2)
        #expect(fromWednesday?.day == 23)
        #expect(fromWednesday?.hour == 9)

        let monday = time(-2 * 24 * 60)
        #expect(components(InboxTimeChoice.nextWeek.date(now: monday, calendar: Self.utc))?.day == 23)

        let sunday = time(4 * 24 * 60)
        #expect(components(InboxTimeChoice.nextWeek.date(now: sunday, calendar: Self.utc))?.day == 23)
    }

    // MARK: Text

    @Test
    func snoozeNoteWords() {
        let locale = Locale(identifier: "en_US")
        let calendar = Self.utc
        let today = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: Self.wednesday) ?? Self.wednesday
        #expect(InboxTimeText.when(today, now: Self.wednesday, calendar: calendar, locale: locale) == "6:00\u{202F}PM")
        let tomorrow = InboxTimeChoice.tomorrow.date(now: Self.wednesday, calendar: calendar) ?? Self.wednesday
        #expect(InboxTimeText.snoozed(until: tomorrow, now: Self.wednesday, calendar: calendar, locale: locale)
            == "Snoozed until tomorrow 9:00\u{202F}AM")
        let monday = InboxTimeChoice.nextWeek.date(now: Self.wednesday, calendar: calendar) ?? Self.wednesday
        #expect(InboxTimeText.when(monday, now: Self.wednesday, calendar: calendar, locale: locale) == "Mon 9:00\u{202F}AM")
    }

    @Test
    func snoozedListShowsTheNoteInPlaceOfThePreview() {
        var inbox = InboxStateDocument()
        inbox.snooze(["!a"], until: time(60), at: time(0))
        let entry = ChatListEntry(row: ChatListRowModel(id: "!a", title: "Alice", preview: "Hi"))
        let visible = ChatListMerging.visible(
            entries: [entry, ChatListEntry(row: ChatListRowModel(id: "!b", title: "Bob"))],
            filter: .inbox,
            labels: ChatLabelDocument(),
            spaces: RoomSpaceMap(),
            document: Self.merges,
            inbox: inbox,
            placement: .snoozed
        ).withSnoozeNotes(inbox: inbox, merges: Self.merges, now: Self.wednesday)
        #expect(visible.ordered.map(\.id) == ["!a"])
        #expect(visible.ordered.first?.row.inboxNote?.hasPrefix("Snoozed until ") == true)
    }
}

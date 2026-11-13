import Foundation
@testable import Models
import Testing

/// MATRIX-157: the day divider label and its refresh when the day changes.
/// Every input is pinned (the clock, the calendar, its time zone, and the
/// locale), so the expectations hold on any machine.
@MainActor
struct DayDividerLabelTests {
    private static let timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static let locale = Locale(identifier: "en_US")

    /// Friday 2026-11-13, 07:49 local: the morning of the bug report.
    private static let morning = date(2026, 11, 13, 7, 49)
    /// Thursday 2026-11-12, 18:46 local: the evening before.
    private static let eveningBefore = date(2026, 11, 12, 18, 46)

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components) else {
            preconditionFailure("invalid test date \(components)")
        }
        return date
    }

    private func text(_ date: Date, now: Date = Self.morning) -> String {
        DayDividerLabel.text(for: date, now: now, calendar: Self.calendar, locale: Self.locale)
    }

    // MARK: - The pure rule

    @Test
    func sameDayReadsToday() {
        #expect(text(Self.date(2026, 11, 13, 0, 0)) == "Today")
        #expect(text(Self.date(2026, 11, 13, 7, 49)) == "Today")
        #expect(text(Self.date(2026, 11, 13, 23, 59)) == "Today")
    }

    /// The bug: 18:46 the evening before is 13 hours back, less than a day
    /// of seconds, but it is yesterday.
    @Test
    func theEveningBeforeReadsYesterday() {
        #expect(text(Self.eveningBefore) == "Yesterday")
        #expect(text(Self.date(2026, 11, 12, 0, 0)) == "Yesterday")
        #expect(text(Self.date(2026, 11, 12, 23, 59), now: Self.date(2026, 11, 13, 0, 1)) == "Yesterday")
    }

    @Test
    func earlierThisWeekReadsTheLongDate() {
        #expect(text(Self.date(2026, 11, 11, 23, 59)) == "November 11, 2026")
        #expect(text(Self.date(2026, 11, 9, 12, 0)) == "November 9, 2026")
    }

    @Test
    func olderReadsTheLongDate() {
        #expect(text(Self.date(2024, 3, 14, 12, 0)) == "March 14, 2024")
    }

    @Test
    func theSameMessageReadsYesterdayFromTheNextDay() {
        let message = Self.eveningBefore
        #expect(text(message, now: Self.date(2026, 11, 12, 23, 59)) == "Today")
        #expect(text(message, now: Self.date(2026, 11, 13, 0, 0)) == "Yesterday")
        #expect(text(message, now: Self.date(2026, 11, 14, 0, 0)) == "November 12, 2026")
    }

    @Test
    func aDateAfterNowReadsToday() {
        #expect(text(Self.date(2026, 11, 14, 9, 0)) == "Today")
    }

    @Test
    func theDayBoundaryFollowsTheCalendarTimeZone() {
        // 2026-11-13 03:00 UTC is still the evening of the 12th in Chicago.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let message = Self.date(2026, 11, 12, 21, 0)
        #expect(DayDividerLabel.bucket(for: message, now: Self.morning, calendar: Self.calendar) == .yesterday)
        #expect(DayDividerLabel.bucket(for: message, now: Self.morning, calendar: utc) == .today)
    }

    // MARK: - The refresh path

    /// A clock and a calendar that a test moves.
    private final class TestClock {
        var now: Date
        var calendar: Calendar

        init(now: Date, calendar: Calendar) {
            self.now = now
            self.calendar = calendar
        }
    }

    private func makeDay(clock: TestClock, center: NotificationCenter) -> CurrentDay {
        CurrentDay(now: { clock.now }, calendar: { clock.calendar }, center: center)
    }

    /// Waits for the main-actor hop of a posted notification.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test
    func refreshChangesTheLabelWhenTheClockPassesMidnight() {
        let clock = TestClock(now: Self.date(2026, 11, 12, 23, 59), calendar: Self.calendar)
        let day = makeDay(clock: clock, center: NotificationCenter())
        #expect(day.dividerLabel(for: Self.eveningBefore, locale: Self.locale) == "Today")

        clock.now = Self.date(2026, 11, 13, 0, 0)
        // No refresh yet: the day is state, not a read of the clock.
        #expect(day.dividerLabel(for: Self.eveningBefore, locale: Self.locale) == "Today")

        day.refresh()
        #expect(day.start == Self.date(2026, 11, 13, 0, 0))
        #expect(day.dividerLabel(for: Self.eveningBefore, locale: Self.locale) == "Yesterday")
    }

    @Test(arguments: CurrentDay.refreshNotifications)
    func aPostedNotificationRefreshesTheDay(name: Notification.Name) async {
        let center = NotificationCenter()
        let clock = TestClock(now: Self.date(2026, 11, 12, 23, 59), calendar: Self.calendar)
        let day = makeDay(clock: clock, center: center)
        #expect(day.dividerLabel(for: Self.eveningBefore, locale: Self.locale) == "Today")

        clock.now = Self.morning
        center.post(name: name, object: nil)
        await waitUntil { day.start == Self.date(2026, 11, 13, 0, 0) }

        #expect(day.dividerLabel(for: Self.eveningBefore, locale: Self.locale) == "Yesterday")
    }

    @Test
    func aTimeZoneChangeMovesTheDayBoundary() async {
        let center = NotificationCenter()
        // 21:00 in Chicago on the 12th is 03:00 UTC on the 13th.
        let clock = TestClock(now: Self.date(2026, 11, 12, 21, 0), calendar: Self.calendar)
        let day = makeDay(clock: clock, center: center)
        let message = Self.date(2026, 11, 12, 9, 0)
        #expect(day.dividerLabel(for: message, locale: Self.locale) == "Today")

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        clock.calendar = utc
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await waitUntil { day.calendar == utc }

        #expect(day.dividerLabel(for: message, locale: Self.locale) == "Yesterday")
    }

    @Test
    func aRefreshOnTheSameDayDoesNotNotifyObservers() {
        let clock = TestClock(now: Self.date(2026, 11, 12, 9, 0), calendar: Self.calendar)
        let day = makeDay(clock: clock, center: NotificationCenter())
        let changes = ChangeCount()
        withObservationTracking {
            _ = day.dividerLabel(for: Self.eveningBefore)
        } onChange: {
            changes.increment()
        }

        clock.now = Self.date(2026, 11, 12, 23, 59)
        day.refresh()
        #expect(changes.value == 0)

        clock.now = Self.date(2026, 11, 13, 0, 0)
        day.refresh()
        #expect(changes.value == 1)
    }

    @Test
    func observedNowReadsTheClockAndTracksTheDay() {
        let clock = TestClock(now: Self.date(2026, 11, 12, 9, 0), calendar: Self.calendar)
        let day = makeDay(clock: clock, center: NotificationCenter())
        let changes = ChangeCount()
        withObservationTracking {
            #expect(day.observedNow == Self.date(2026, 11, 12, 9, 0))
        } onChange: {
            changes.increment()
        }

        clock.now = Self.morning
        day.refresh()
        #expect(changes.value == 1)
        #expect(day.observedNow == Self.morning)
        // The chat list's bucket for the evening before follows the day.
        let stamp = ChatListTimestamp.text(
            for: Self.eveningBefore,
            now: day.observedNow,
            calendar: Self.calendar,
            locale: Self.locale
        )
        #expect(stamp == "Yesterday")
    }
}

/// Counts `withObservationTracking` change calls, which are `@Sendable`.
private final class ChangeCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

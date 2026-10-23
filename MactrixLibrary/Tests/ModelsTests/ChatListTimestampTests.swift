import Foundation
@testable import Models
import Testing

/// MATRIX-67: the chat-list timestamp buckets. Every input is pinned — `now`,
/// the calendar, its time zone, and the locale — so the expectations hold on
/// any machine.
struct ChatListTimestampTests {
    private static let timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static let locale = Locale(identifier: "en_US")

    /// Thursday 2026-10-22, 10:00 local.
    private static let now = date(2026, 10, 22, 10, 0)

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components) else {
            preconditionFailure("invalid test date \(components)")
        }
        return date
    }

    private func text(_ date: Date, locale: Locale = Self.locale) -> String {
        ChatListTimestamp.text(for: date, now: Self.now, calendar: Self.calendar, locale: locale)
    }

    @Test
    func todayShowsShortTime() {
        let result = text(Self.date(2026, 10, 22, 9, 5))
        // The narrow no-break space ICU puts before the day period varies by
        // OS release, so compare with whitespace normalized.
        #expect(result.replacingOccurrences(of: "\u{202F}", with: " ") == "9:05 AM")
    }

    @Test
    func todayFollowsTheLocale() {
        let result = text(Self.date(2026, 10, 22, 15, 42), locale: Locale(identifier: "de_DE"))
        #expect(result == "15:42")
    }

    @Test
    func justAfterMidnightIsToday() {
        #expect(text(Self.date(2026, 10, 22, 0, 1)).contains("12:01"))
    }

    @Test
    func yesterdayByCalendarDay() {
        #expect(text(Self.date(2026, 10, 21, 23, 58)) == "Yesterday")
        #expect(text(Self.date(2026, 10, 21, 0, 0)) == "Yesterday")
    }

    @Test
    func withinSixDaysShowsWeekday() {
        // Tuesday, two days back.
        #expect(text(Self.date(2026, 10, 20, 12, 0)) == "Tue")
        // Friday, six days back: the last day of the window.
        #expect(text(Self.date(2026, 10, 16, 12, 0)) == "Fri")
    }

    @Test
    func olderShowsShortNumericDate() {
        // Seven days back leaves the weekday window.
        #expect(text(Self.date(2026, 10, 15, 12, 0)) == "10/15/26")
        #expect(text(Self.date(2025, 1, 3, 12, 0)) == "1/3/25")
    }

    /// Server clock skew can put the latest event a little in the future.
    @Test
    func futureTimestampShowsTime() {
        #expect(text(Self.date(2026, 10, 23, 0, 30)).contains("12:30"))
    }
}

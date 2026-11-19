import Foundation
@testable import Models
import Testing

/// MATRIX-207: the typed time of the "Custom…" sheet.
///
/// Calendar: Gregorian, America/Chicago. Locale: en_US.
///
/// `NSDataDetector` has no reference date: it reads "tomorrow" and "fri"
/// against the system clock. The tests that go through the detector use a
/// `now` on the system's today at a fixed hour, and check the result against
/// that day. The short forms and the absolute dates use a fixed `now`
/// (Wednesday 2026-11-18 10:00 in Chicago).
struct TimeInputParserTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        calendar.locale = locale
        return calendar
    }

    private static let locale = Locale(identifier: "en_US")

    /// Wednesday 2026-11-18 10:00 in Chicago (16:00 UTC).
    private static let wednesday = Date(timeIntervalSince1970: 1_795_017_600)

    /// The system's today at `hour`:00 in the test calendar. The detector
    /// puts "today" on the system's day.
    private static func today(at hour: Int) -> Date {
        var system = Calendar(identifier: .gregorian)
        system.timeZone = .current
        var day = system.dateComponents([.year, .month, .day], from: .now)
        day.hour = hour
        return calendar.date(from: day) ?? .now
    }

    private func parse(_ text: String, now: Date = wednesday) -> TimeInputResult {
        TimeInputParser(now: now, calendar: Self.calendar).parse(text)
    }

    private func components(_ date: Date?) -> DateComponents? {
        date.map { Self.calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: $0) }
    }

    /// Whole days from the start of `now`'s day to the start of `date`'s day.
    private func dayOffset(_ date: Date?, from now: Date) -> Int? {
        date.flatMap {
            Self.calendar.dateComponents(
                [.day],
                from: Self.calendar.startOfDay(for: now),
                to: Self.calendar.startOfDay(for: $0)
            ).day
        }
    }

    @Test
    func wednesdayIsTheFixedNow() {
        let parts = components(Self.wednesday)
        #expect(parts?.weekday == 4)
        #expect(parts?.hour == 10)
        #expect(parts?.day == 18)
    }

    // MARK: Empty and garbage

    @Test
    func emptyTextIsEmpty() {
        #expect(parse("") == .empty)
        #expect(parse("   ") == .empty)
    }

    @Test
    func garbageIsNotATime() {
        #expect(parse("asdf qwer") == .invalid(.notATime))
        #expect(parse("banana") == .invalid(.notATime))
    }

    // MARK: Short forms (the one rule of our own)

    @Test
    func inTwoHours() {
        // NSDataDetector finds no date in "in 2 hours"; the short-form rule
        // reads it.
        #expect(parse("in 2 hours") == .valid(Self.wednesday.addingTimeInterval(2 * 3600)))
    }

    @Test
    func shortForms() {
        #expect(parse("2h") == .valid(Self.wednesday.addingTimeInterval(2 * 3600)))
        #expect(parse("30m") == .valid(Self.wednesday.addingTimeInterval(30 * 60)))
        #expect(parse("30 min") == .valid(Self.wednesday.addingTimeInterval(30 * 60)))
        #expect(parse("2 hrs") == .valid(Self.wednesday.addingTimeInterval(2 * 3600)))
        #expect(parse("in 45 minutes") == .valid(Self.wednesday.addingTimeInterval(45 * 60)))
        #expect(parse("3D") == .valid(Self.wednesday.addingTimeInterval(3 * 86400)))
    }

    @Test
    func inOneDayIsTwentyFourHours() {
        // NSDataDetector reads "in 1 day" as tomorrow at 12:00. The short-form
        // rule runs first, so it is 24 hours from now.
        #expect(parse("in 1 day") == .valid(Self.wednesday.addingTimeInterval(86400)))
    }

    @Test
    func tooSoon() {
        #expect(parse("0m") == .invalid(.tooSoon))
        #expect(parse("1m") == .valid(Self.wednesday.addingTimeInterval(60)))
    }

    @Test
    func moreThanAYearIsTooFar() {
        #expect(parse("365d") == .valid(Self.wednesday.addingTimeInterval(365 * 86400)))
        #expect(parse("366d") == .invalid(.tooFar))
        #expect(parse("Dec 1 2030") == .invalid(.tooFar))
    }

    // MARK: Absolute dates

    @Test
    func pastDateHasPassed() {
        #expect(parse("Jan 1 2020") == .invalid(.passed))
        #expect(parse("Nov 17 2026 9am") == .invalid(.passed))
    }

    @Test
    func dateWithNoTimeIsNoon() {
        // NSDataDetector puts a date with no time at 12:00.
        let parts = components(parse("Dec 25 2026").date)
        #expect(parts?.month == 12)
        #expect(parts?.day == 25)
        #expect(parts?.hour == 12)
    }

    // MARK: Natural language (NSDataDetector, against the system's today)

    @Test
    func tomorrowThreePM() {
        let now = Self.today(at: 10)
        let date = parse("tomorrow 3pm", now: now).date
        #expect(dayOffset(date, from: now) == 1)
        #expect(components(date)?.hour == 15)
        #expect(components(date)?.minute == 0)
    }

    @Test
    func fridayNineAM() {
        let now = Self.today(at: 10)
        let date = parse("fri 9am", now: now).date
        #expect(components(date)?.weekday == 6)
        #expect(components(date)?.hour == 9)
        // The next Friday: on a Friday, NSDataDetector gives the Friday a
        // week later (seen with "thu 9am" on a Thursday).
        let offset = dayOffset(date, from: now) ?? 0
        #expect((1 ... 7).contains(offset))
    }

    @Test
    func nineAMBeforeNine() {
        let now = Self.today(at: 8)
        let date = parse("9am", now: now).date
        #expect(dayOffset(date, from: now) == 0)
        #expect(components(date)?.hour == 9)
    }

    @Test
    func nineAMAfterNineRollsToTomorrow() {
        // NSDataDetector gives today 9:00, in the past; a time with no date
        // moves to the next day.
        let now = Self.today(at: 10)
        let date = parse("9am", now: now).date
        #expect(dayOffset(date, from: now) == 1)
        #expect(components(date)?.hour == 9)
    }

    @Test
    func todayNineAMAfterNineAlsoRolls() {
        // NSDataDetector does not tell if the text named a date, so the
        // same-day rule moves "today 9am" too.
        let now = Self.today(at: 10)
        #expect(dayOffset(parse("today 9am", now: now).date, from: now) == 1)
    }

    @Test
    func nextWeekIsNotATime() {
        // NSDataDetector finds no date in "next week" (or "next month",
        // "1 week", "at 9"). The Monday 9 AM preset covers next week.
        #expect(parse("next week", now: Self.today(at: 10)) == .invalid(.notATime))
        #expect(parse("at 9", now: Self.today(at: 10)) == .invalid(.notATime))
    }

    // MARK: Presets

    @Test
    func presets() {
        let now = Self.wednesday
        let calendar = Self.calendar
        #expect(TimeChoicePreset.thirtyMinutes.date(now: now, calendar: calendar) == now.addingTimeInterval(1800))
        #expect(TimeChoicePreset.threeHours.date(now: now, calendar: calendar) == now.addingTimeInterval(3 * 3600))
        let tomorrow = components(TimeChoicePreset.tomorrowMorning.date(now: now, calendar: calendar))
        #expect(tomorrow?.day == 19)
        #expect(tomorrow?.hour == 9)
        let monday = components(TimeChoicePreset.mondayMorning.date(now: now, calendar: calendar))
        #expect(monday?.day == 23)
        #expect(monday?.weekday == 2)
        #expect(monday?.hour == 9)
        // On a Monday, the next Monday.
        let mondayNow = now.addingTimeInterval(5 * 86400)
        #expect(components(TimeChoicePreset.mondayMorning.date(now: mondayNow, calendar: calendar))?.day == 30)
    }

    // MARK: Preview words

    @Test
    func previewWords() {
        let friday = Self.wednesday.addingTimeInterval(2 * 86400 + 5 * 3600)
        #expect(TimeInputText.full(friday, now: Self.wednesday, calendar: Self.calendar, locale: Self.locale)
            == "Friday, Nov 20 at 3:00\u{202F}PM")
        #expect(TimeInputText.relative(friday, now: Self.wednesday, calendar: Self.calendar, locale: Self.locale)
            == "in 2 days")
        let twoHours = Self.wednesday.addingTimeInterval(2 * 3600)
        #expect(TimeInputText.relative(twoHours, now: Self.wednesday, calendar: Self.calendar, locale: Self.locale)
            == "in 2 hours")
        let nextYear = Self.wednesday.addingTimeInterval(60 * 86400)
        #expect(TimeInputText.full(nextYear, now: Self.wednesday, calendar: Self.calendar, locale: Self.locale)
            == "Sunday, Jan 17, 2027 at 10:00\u{202F}AM")
    }
}

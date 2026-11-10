import Foundation
@testable import Models
import Testing

/// MATRIX-136: which day the floating sticky day pill shows.
struct TimelineStickyDayTests {
    /// A fixed zone, so "the start of the day" does not depend on the machine.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// 2026-10-23 00:00:00 UTC.
    private static let dayOne = Date(timeIntervalSince1970: 1_792_713_600)
    /// 2026-10-24 00:00:00 UTC.
    private static let dayTwo = dayOne.addingTimeInterval(24 * 3600)

    private func message(_ id: String, at date: Date) -> TimelineRow {
        .message(
            uniqueId: id,
            event: GroupingTestEvent(sender: "@ada:example.org", date: date),
            kind: .text,
            heightFingerprint: .stub()
        )
    }

    private func state(_ id: String, at date: Date) -> TimelineRow {
        .state(uniqueId: id, event: GroupingTestEvent(sender: "@ada:example.org", date: date), name: "joined")
    }

    private func divider(_ id: String, _ date: Date) -> TimelineRow {
        .virtual(uniqueId: id, item: .dateDivider(date: date))
    }

    private func day(_ rows: [TimelineRow], _ edge: Range<Int>) -> Date? {
        TimelineStickyDay.day(rows: rows, rowsAtTopEdge: edge, calendar: Self.calendar)
    }

    /// Newest first, as the table holds them:
    /// 0 typing, 1-2 day two messages, 3 day two divider, 4 read marker,
    /// 5 day one state event, 6 day one message, 7 day one divider,
    /// 8 timeline start, 9 pagination activity.
    private var rows: [TimelineRow] {
        [
            .typingIndicator(uniqueId: "typing", names: ["Ada"]),
            message("m4", at: Self.dayTwo.addingTimeInterval(3600 * 9)),
            message("m3", at: Self.dayTwo.addingTimeInterval(3600 * 8)),
            divider("d2", Self.dayTwo),
            .virtual(uniqueId: "marker", item: .readMarker),
            state("s2", at: Self.dayOne.addingTimeInterval(3600 * 22)),
            message("m1", at: Self.dayOne.addingTimeInterval(3600 * 7)),
            divider("d1", Self.dayOne),
            .virtual(uniqueId: "start", item: .timelineStart),
            .paginationActivity(uniqueId: "pagination"),
        ]
    }

    @Test func showsTheDayOfTheTopmostMessage() {
        // Rows 1 and 2 are under the pill; row 2 is the topmost.
        #expect(day(rows, 1 ..< 3) == Self.dayTwo)
    }

    @Test func returnsTheStartOfTheDay() {
        let date = day(rows, 6 ..< 7)
        #expect(date == Self.dayOne)
        #expect(date != Self.dayOne.addingTimeInterval(3600 * 7))
    }

    @Test func aStateEventCarriesItsDay() {
        #expect(day(rows, 5 ..< 6) == Self.dayOne)
    }

    @Test func hidesWhileADateDividerIsUnderThePill() {
        #expect(day(rows, 3 ..< 4) == nil)
        // The divider is under the pill but not the topmost row.
        #expect(day(rows, 2 ..< 5) == nil)
        #expect(day(rows, 6 ..< 8) == nil)
    }

    @Test func aRowWithoutADateTakesTheNearestOlderDay() {
        // The read marker sits below the day two divider, in day one.
        #expect(day(rows, 4 ..< 5) == Self.dayOne)
    }

    @Test func fallsBackToTheNearestNewerDayAtTheOldestEnd() {
        // Nothing older than the pagination row has a date.
        #expect(day(rows, 9 ..< 10) == Self.dayOne)
    }

    @Test func hidesWithNoRowsUnderThePill() {
        #expect(day(rows, 0 ..< 0) == nil)
        #expect(day([], 0 ..< 1) == nil)
    }

    @Test func ignoresIndicesPastTheRows() {
        #expect(day(Array(rows.prefix(3)), 1 ..< 40) == Self.dayTwo)
    }

    @Test func hidesWhenNoRowCarriesADate() {
        let undated: [TimelineRow] = [
            .typingIndicator(uniqueId: "typing", names: ["Ada"]),
            .virtual(uniqueId: "start", item: .timelineStart),
        ]
        #expect(day(undated, 1 ..< 2) == nil)
    }
}

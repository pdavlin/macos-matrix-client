import Foundation

/// The text a day divider shows for a date (MATRIX-136, MATRIX-157).
///
/// Three buckets, keyed on calendar days rather than elapsed hours, so a
/// message from yesterday evening never reads "Today" the next morning:
///
/// - the same day as `now`, or later (clock skew): "Today";
/// - the day before: "Yesterday";
/// - anything older: the long date ("March 14, 2024").
///
/// The rule is pure. `CurrentDay` supplies `now` and `calendar` to the views
/// and changes when the day changes.
public enum DayDividerLabel {
    /// The bucket of a date, relative to the day of `now`.
    public enum Bucket: Equatable, Sendable {
        case today
        case yesterday
        case date
    }

    public static func bucket(for date: Date, now: Date = .now, calendar: Calendar = .current) -> Bucket {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        switch days {
        case ...0:
            return .today
        case 1:
            return .yesterday
        default:
            return .date
        }
    }

    public static func text(
        for date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        switch bucket(for: date, now: now, calendar: calendar) {
        case .today:
            return String(localized: "Today")
        case .yesterday:
            return String(localized: "Yesterday")
        case .date:
            let style = Date.FormatStyle(
                date: .long,
                time: .omitted,
                locale: locale,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
            return date.formatted(style)
        }
    }
}

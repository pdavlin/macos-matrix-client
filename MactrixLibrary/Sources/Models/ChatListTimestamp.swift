import Foundation

/// The timestamp text a chat-list row shows beside the room title (MATRIX-67).
///
/// Four buckets, keyed on calendar days rather than elapsed hours, so a
/// message from 23:58 reads "Yesterday" two minutes after midnight:
///
/// - today: a short, locale-aware time ("3:42 PM", "15:42");
/// - yesterday: "Yesterday";
/// - two to six days back: the abbreviated weekday ("Tue");
/// - anything older: a short numeric date.
///
/// A timestamp later than `now` (clock skew between servers) on the same or a
/// later day reads as a time, so the row never claims a future date.
public enum ChatListTimestamp {
    /// Days back, inclusive, that still show a weekday instead of a date.
    public static let weekdayWindowDays = 6

    public static func text(
        for date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)

        switch days {
        case ...0:
            style = style.hour().minute()
        case 1:
            return "Yesterday"
        case 2 ... weekdayWindowDays:
            style = style.weekday(.abbreviated)
        default:
            style = style.year(.twoDigits).month(.defaultDigits).day(.defaultDigits)
        }

        return date.formatted(style)
    }
}

import Foundation

// MATRIX-207: the typed time of the "Custom…" sheet. MATRIX-212 (Send
// Later) uses the same parser and sheet.

/// Why a typed time is not usable.
public enum TimeInputProblem: Equatable, Sendable {
    /// The text holds no time.
    case notATime
    /// The time is in the past.
    case passed
    /// The time is less than `TimeInputParser.minimumLead` ahead.
    case tooSoon
    /// The time is more than `TimeInputParser.maximumDays` ahead.
    case tooFar

    /// The words of the sheet's preview line.
    public var message: String {
        switch self {
        case .notATime: "Not a time"
        case .passed: "That time has passed"
        case .tooSoon: "Pick a time at least a minute from now"
        case .tooFar: "Pick a time within a year"
        }
    }
}

/// The result of a typed time.
public enum TimeInputResult: Equatable, Sendable {
    /// No text.
    case empty
    /// A usable time.
    case valid(Date)
    /// Text that gives no usable time.
    case invalid(TimeInputProblem)

    /// The usable time, if any.
    public var date: Date? {
        guard case let .valid(date) = self else { return nil }
        return date
    }
}

/// Reads a typed time: "in 2 hours", "2h", "tomorrow 3pm", "fri 9am".
///
/// Natural language goes to `NSDataDetector` (`.date`). One small rule comes
/// first, for the short forms the detector does not find: a number and a
/// unit (m, min, minute; h, hr, hour; d, day; singular or plural, with or
/// without "in"), counted from `now`.
///
/// Rules on the result:
/// - A past time on the same day as `now` moves to the next day. The
///   detector puts a time with no date ("9am") on today, and it does not
///   tell if the text named a date, so "today 9am" after 9:00 also moves.
/// - Any other past time is `.passed`.
/// - The time must be at least `minimumLead` after `now`.
/// - The time must be at most `maximumDays` after `now` (the Synapse
///   delayed-event maximum, for Send Later).
///
/// The detector reads the text against the system clock and the system time
/// zone; it has no reference date. The parser keeps the wall-clock time the
/// detector found and puts it in `calendar`'s time zone, so a calendar with
/// another time zone reads "3pm" as 3 PM there. `now` sets the rules and the
/// short forms only.
public struct TimeInputParser: Sendable {
    /// The least time ahead a result may be.
    public static let minimumLead: TimeInterval = 60
    /// The most days ahead a result may be.
    public static let maximumDays = 365

    public let now: Date
    public let calendar: Calendar

    public init(now: Date, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    /// The latest time a result may be.
    public var latest: Date {
        calendar.date(byAdding: .day, value: Self.maximumDays, to: now) ?? now
    }

    /// The earliest time a result may be.
    public var earliest: Date {
        now.addingTimeInterval(Self.minimumLead)
    }

    /// Reads `text`.
    public func parse(_ text: String) -> TimeInputResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if let date = shortForm(trimmed) {
            return check(date)
        }
        guard var date = detected(trimmed) else { return .invalid(.notATime) }
        if date < now {
            guard calendar.isDate(date, inSameDayAs: now),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: date)
            else { return .invalid(.passed) }
            date = nextDay
        }
        return check(date)
    }

    /// Checks `date` against `now`: not in the past, at least
    /// `minimumLead` ahead, at most `maximumDays` ahead.
    public func check(_ date: Date) -> TimeInputResult {
        if date < now {
            return .invalid(.passed)
        }
        if date < earliest {
            return .invalid(.tooSoon)
        }
        if date > latest {
            return .invalid(.tooFar)
        }
        return .valid(date)
    }

    // MARK: - Short forms

    /// "2h", "30m", "30 min", "2 hrs", "in 2 hours", "3d".
    private static let shortFormPattern = #"^(?:in\s+)?(\d{1,6})\s*(m|mins?|minutes?|h|hrs?|hours?|d|days?)$"#

    private func shortForm(_ text: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: Self.shortFormPattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let number = Int(text[numberRange])
        else { return nil }
        switch text[unitRange].lowercased().first {
        case "m": return calendar.date(byAdding: .minute, value: number, to: now)
        case "h": return calendar.date(byAdding: .hour, value: number, to: now)
        case "d": return calendar.date(byAdding: .day, value: number, to: now)
        default: return nil
        }
    }

    // MARK: - NSDataDetector

    /// The first date the detector finds in `text`, in `calendar`'s time
    /// zone.
    private func detected(_ text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let found = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.date
        else { return nil }
        var system = Calendar(identifier: .gregorian)
        system.timeZone = .current
        guard system.timeZone != calendar.timeZone else { return found }
        let wallClock = system.dateComponents([.year, .month, .day, .hour, .minute, .second], from: found)
        return calendar.date(from: wallClock)
    }
}

/// The quick choices on top of the time sheet: each one picks its time at
/// once.
public enum TimeChoicePreset: String, CaseIterable, Sendable, Identifiable {
    case thirtyMinutes
    case threeHours
    case tomorrowMorning
    case mondayMorning

    public var id: Self { self }

    /// The hour "tomorrow" and "Monday" mean.
    static let morningHour = 9

    /// The button title.
    public var title: String {
        switch self {
        case .thirtyMinutes: "In 30 Minutes"
        case .threeHours: "In 3 Hours"
        case .tomorrowMorning: "Tomorrow 9 AM"
        case .mondayMorning: "Monday 9 AM"
        }
    }

    /// The time this choice means at `now`. "Monday" is the next Monday
    /// after today.
    public func date(now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .thirtyMinutes:
            return calendar.date(byAdding: .minute, value: 30, to: now)
        case .threeHours:
            return calendar.date(byAdding: .hour, value: 3, to: now)
        case .tomorrowMorning:
            guard let day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
            return calendar.date(bySettingHour: Self.morningHour, minute: 0, second: 0, of: day)
        case .mondayMorning:
            guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
                return nil
            }
            return calendar.nextDate(
                after: startOfTomorrow.addingTimeInterval(-1),
                matching: DateComponents(hour: Self.morningHour, minute: 0, second: 0, weekday: 2),
                matchingPolicy: .nextTime
            )
        }
    }
}

/// The words of the time sheet's preview line.
public enum TimeInputText {
    /// "Friday, Nov 21 at 3:00 PM", with the year when it is not the year
    /// of `now`.
    public static func full(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = formatted(date, template: sameYear ? "EEEEMMMd" : "EEEEMMMdy", calendar: calendar, locale: locale)
        let time = formatted(date, template: "jmm", calendar: calendar, locale: locale)
        return "\(day) at \(time)"
    }

    /// "in 2 hours", "in 1 day".
    public static func relative(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private static func formatted(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

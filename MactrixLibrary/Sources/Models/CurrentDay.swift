import Foundation
import Observation

/// The current calendar day, as observable state (MATRIX-157).
///
/// A relative date text ("Today", "Yesterday", a chat-list time) is correct
/// only for the day it was made on. A view that reads `start` or `calendar`
/// in its body draws again when the day changes while the app runs: at
/// midnight (`NSCalendarDayChanged`, also posted on wake), on a time-zone
/// change, and on a system clock change.
///
/// Usage (in a SwiftUI body):
/// ```swift
/// Text(CurrentDay.shared.dividerLabel(for: date))
/// ```
@MainActor @Observable
public final class CurrentDay {
    /// The day of the running app.
    public static let shared = CurrentDay()

    /// The notifications that can move the day boundary.
    public nonisolated static let refreshNotifications: [Notification.Name] = [
        .NSCalendarDayChanged,
        .NSSystemTimeZoneDidChange,
        .NSSystemClockDidChange,
    ]

    /// The start of the current day in `calendar`.
    public private(set) var start: Date
    /// The calendar, with the time zone, that `start` was computed in.
    public private(set) var calendar: Calendar

    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let currentCalendar: @MainActor () -> Calendar
    @ObservationIgnored private let observers: Observers

    /// - Parameters:
    ///   - now: the clock. Tests inject a fixed one.
    ///   - calendar: the current calendar, read again on each refresh.
    ///   - center: the notification center that posts `refreshNotifications`.
    public init(
        now: @escaping @MainActor () -> Date = { .now },
        calendar: @escaping @MainActor () -> Calendar = { .current },
        center: NotificationCenter = .default
    ) {
        clock = now
        currentCalendar = calendar
        let initialCalendar = calendar()
        self.calendar = initialCalendar
        start = initialCalendar.startOfDay(for: now())
        observers = Observers(center: center)
        // The system posts these on any thread, so hop to the main actor.
        observers.tokens = Self.refreshNotifications.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        }
    }

    /// Reads the clock and the calendar again. Observers are told only when
    /// the day or the calendar did change.
    public func refresh() {
        let newCalendar = currentCalendar()
        let newStart = newCalendar.startOfDay(for: clock())
        if newCalendar != calendar {
            calendar = newCalendar
        }
        if newStart != start {
            start = newStart
        }
    }

    /// The current time. A body that reads it also draws again when the day
    /// changes.
    public var observedNow: Date {
        _ = start
        return clock()
    }

    /// The day divider text of `date`, relative to the current day.
    public func dividerLabel(for date: Date, locale: Locale = .current) -> String {
        DayDividerLabel.text(for: date, now: start, calendar: calendar, locale: locale)
    }

    /// Owns the observer tokens and removes them when the day goes away.
    private final class Observers: @unchecked Sendable {
        let center: NotificationCenter
        var tokens: [any NSObjectProtocol] = []

        init(center: NotificationCenter) {
            self.center = center
        }

        deinit {
            tokens.forEach(center.removeObserver)
        }
    }
}

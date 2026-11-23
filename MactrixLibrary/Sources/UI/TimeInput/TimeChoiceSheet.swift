import Models
import SwiftUI

/// One quick choice on top of the time sheet: a title and the time it
/// picks at once (MATRIX-212).
public struct TimeQuickChoice: Identifiable, Sendable {
    public let title: String
    public let date: Date

    public var id: String { title }

    public init(title: String, date: Date) {
        self.title = title
        self.date = date
    }
}

/// A sheet that asks for a time ahead (MATRIX-207; MATRIX-212 Send Later
/// uses it too).
///
/// On top, the title and an optional detail view (Send Later puts the
/// message there). Then quick-choice buttons that pick their time at once.
/// Then a text field for a typed time ("in 2 hours", "tomorrow 3pm",
/// "fri 9am"), read by `TimeInputParser`, with a preview line under it.
/// Then a field-style date picker that follows the typed time; an edit in
/// it becomes the chosen time. Return picks the chosen time, Esc cancels.
public struct TimeChoiceSheet<Detail: View>: View {
    let title: String
    let confirmLabel: String
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let quickChoices: [TimeQuickChoice]
    /// False turns the confirm button and the quick choices off.
    let canConfirm: Bool
    let detail: Detail
    let choose: (Date) -> Void
    let cancel: () -> Void

    @State private var text: String
    /// The date picker's value: the typed time, or the user's own edit.
    @State private var picked: Date
    /// The user changed the date picker after the last typed time, or the
    /// sheet started at a given time.
    @State private var isPickerEdited: Bool
    @State private var isDone = false
    @FocusState private var isFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - title: the sheet's title, as "Snooze Alice until".
    ///   - confirmLabel: the confirm button, as "Snooze".
    ///   - now: the time the choices count from.
    ///   - calendar: the calendar and time zone of the times.
    ///   - locale: the locale of the preview line.
    ///   - quickChoices: the buttons on top.
    ///   - text: the text the field starts with.
    ///   - initialDate: the time the sheet starts at, with an empty field.
    ///     Nil starts at the typed text's time.
    ///   - canConfirm: false turns the confirm button and the quick choices
    ///     off.
    ///   - detail: the view under the title.
    ///   - choose: gets the chosen time. The sheet then closes.
    ///   - cancel: runs on Cancel or Esc. The sheet then closes.
    public init(
        title: String,
        confirmLabel: String,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current,
        quickChoices: [TimeQuickChoice],
        text: String = "",
        initialDate: Date? = nil,
        canConfirm: Bool = true,
        @ViewBuilder detail: () -> Detail,
        choose: @escaping (Date) -> Void,
        cancel: @escaping () -> Void = {}
    ) {
        self.title = title
        self.confirmLabel = confirmLabel
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.quickChoices = quickChoices
        self.canConfirm = canConfirm
        self.detail = detail()
        self.choose = choose
        self.cancel = cancel
        let parser = TimeInputParser(now: now, calendar: calendar)
        _text = State(initialValue: text)
        _isPickerEdited = State(initialValue: initialDate != nil)
        _picked = State(
            initialValue: initialDate
                ?? parser.parse(text).date
                ?? TimeChoicePreset.tomorrowMorning.date(now: now, calendar: calendar)
                ?? parser.earliest
        )
    }

    private var parser: TimeInputParser {
        TimeInputParser(now: now, calendar: calendar)
    }

    private var result: TimeInputResult {
        parser.parse(text)
    }

    /// The time Confirm and Return pick, if any.
    private var chosen: Date? {
        isPickerEdited ? parser.check(picked).date : result.date
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            detail
            HStack(spacing: 6) {
                ForEach(quickChoices) { choice in
                    Button(choice.title) { finish(choice.date) }
                        .controlSize(.small)
                }
            }
            .disabled(!canConfirm)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Time", text: $text, prompt: Text("in 2 hours, tomorrow 3pm, fri 9am"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($isFieldFocused)
                preview
                    .font(.callout)
                    .lineLimit(1)
            }
            datePicker
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(confirmLabel) {
                    if let chosen { finish(chosen) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen == nil || !canConfirm)
            }
        }
        .padding(20)
        .frame(width: 440)
        .environment(\.locale, locale)
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .defaultFocus($isFieldFocused, true)
        .onAppear { isFieldFocused = true }
        .onChange(of: text) {
            isPickerEdited = false
            if let date = result.date {
                picked = date
            }
        }
    }

    /// The parsed time in full and how far ahead, or why there is none.
    @ViewBuilder
    private var preview: some View {
        if isPickerEdited {
            previewLine(for: parser.check(picked))
        } else {
            previewLine(for: result)
        }
    }

    @ViewBuilder
    private func previewLine(for result: TimeInputResult) -> some View {
        switch result {
        case .empty:
            Text("Type a time, like tomorrow 3pm")
                .foregroundStyle(.tertiary)
        case let .valid(date):
            HStack(spacing: 6) {
                Text(TimeInputText.full(date, now: now, calendar: calendar, locale: locale))
                Text(TimeInputText.relative(date, now: now, calendar: calendar, locale: locale))
                    .foregroundStyle(.secondary)
            }
        case let .invalid(problem):
            Text(problem.message)
                .foregroundStyle(.secondary)
        }
    }

    private var datePicker: some View {
        DatePicker(
            "Time",
            selection: Binding(
                get: { picked },
                set: { date in
                    guard date != picked else { return }
                    picked = date
                    isPickerEdited = true
                }
            ),
            in: parser.earliest ... parser.latest,
            displayedComponents: [.date, .hourAndMinute]
        )
        .labelsHidden()
        #if os(macOS)
            .datePickerStyle(.stepperField)
        #else
            .datePickerStyle(.compact)
        #endif
    }

    private func finish(_ date: Date) {
        guard !isDone, canConfirm else { return }
        isDone = true
        choose(date)
        dismiss()
    }
}

public extension TimeChoiceSheet where Detail == EmptyView {
    /// The sheet with no detail view and `TimeChoicePreset` buttons
    /// (MATRIX-207). See the main initializer.
    init(
        title: String,
        confirmLabel: String,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current,
        presets: [TimeChoicePreset] = TimeChoicePreset.allCases,
        text: String = "",
        choose: @escaping (Date) -> Void,
        cancel: @escaping () -> Void = {}
    ) {
        self.init(
            title: title,
            confirmLabel: confirmLabel,
            now: now,
            calendar: calendar,
            locale: locale,
            quickChoices: presets.compactMap { preset in
                preset.date(now: now, calendar: calendar).map { TimeQuickChoice(title: preset.title, date: $0) }
            },
            text: text,
            detail: { EmptyView() },
            choose: choose,
            cancel: cancel
        )
    }
}

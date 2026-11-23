import Models
import SwiftUI

/// The time choices of Send Later (MATRIX-212): the Snooze and Remind me
/// later choices of MATRIX-207 ("In 1 Hour", "This Evening", "Tomorrow",
/// "Next Week"). A choice that has passed ("This Evening" after 18:00) is
/// left out.
enum SendLaterChoices {
    static func quickChoices(now: Date, calendar: Calendar) -> [TimeQuickChoice] {
        InboxTimeChoice.allCases.compactMap { choice in
            choice.date(now: now, calendar: calendar).map { TimeQuickChoice(title: choice.remindTitle, date: $0) }
        }
    }
}

/// The Send Later sheet for the composer's message (MATRIX-212).
///
/// The message shows under the title as it will be sent: plain text, with
/// each mention as "@name". When the composer had a mention or formatting,
/// a note says that the message sends as plain text. The time choices are
/// MATRIX-207's, with the typed time and the date picker of
/// `TimeChoiceSheet`. Times show in the calendar's (the local) time zone.
public struct SendLaterSheet: View {
    let chatName: String
    let text: ScheduledMessageText
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let schedule: (Date) -> Void

    /// - Parameters:
    ///   - chatName: the chat, for the title.
    ///   - text: the message and whether it loses formatting.
    ///   - now: the time the choices count from.
    ///   - calendar: the calendar and time zone of the times.
    ///   - locale: the locale of the times.
    ///   - schedule: gets the chosen time. The sheet then closes.
    public init(
        chatName: String,
        text: ScheduledMessageText,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current,
        schedule: @escaping (Date) -> Void
    ) {
        self.chatName = chatName
        self.text = text
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.schedule = schedule
    }

    public var body: some View {
        TimeChoiceSheet(
            title: "Send to \(chatName) later",
            confirmLabel: "Schedule",
            now: now,
            calendar: calendar,
            locale: locale,
            quickChoices: SendLaterChoices.quickChoices(now: now, calendar: calendar),
            detail: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text.body)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    if text.losesFormatting {
                        Label(ScheduledMessageText.plainTextNote, systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            },
            choose: schedule
        )
    }
}

/// The Edit sheet of a scheduled message (MATRIX-212): the text in an
/// editor, and the time, which starts at the message's time. Save cancels
/// the message and schedules the new text.
public struct SendLaterEditSheet: View {
    let chatName: String
    let sendAt: Date
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let save: (String, Date) -> Void

    @State private var text: String

    /// - Parameters:
    ///   - chatName: the chat, for the title.
    ///   - text: the message's text.
    ///   - sendAt: the message's time.
    ///   - now: the time the choices count from.
    ///   - calendar: the calendar and time zone of the times.
    ///   - locale: the locale of the times.
    ///   - save: gets the new text and time. The sheet then closes.
    public init(
        chatName: String,
        text: String,
        sendAt: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current,
        save: @escaping (String, Date) -> Void
    ) {
        self.chatName = chatName
        self.sendAt = sendAt
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.save = save
        _text = State(initialValue: text)
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        TimeChoiceSheet(
            title: "Edit message to \(chatName)",
            confirmLabel: "Save",
            now: now,
            calendar: calendar,
            locale: locale,
            quickChoices: SendLaterChoices.quickChoices(now: now, calendar: calendar),
            initialDate: sendAt,
            canConfirm: !trimmedText.isEmpty,
            detail: {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(height: 80)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            },
            choose: { date in save(trimmedText, date) }
        )
    }
}

#Preview {
    SendLaterSheet(
        chatName: "Design Team",
        text: ScheduledMessageText(draftText: "Lunch at **noon**?"),
        schedule: { _ in }
    )
}

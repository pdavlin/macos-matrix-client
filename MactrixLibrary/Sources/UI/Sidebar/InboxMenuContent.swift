import Models
import SwiftUI

/// A chat's inbox items (MATRIX-206, MATRIX-207): Archive or Unarchive,
/// Snooze or Unsnooze, and Remind Me Later or Cancel Reminder. The row
/// menus and ⌘K show the same items.
public struct InboxMenuContent: View {
    let placement: InboxPlacement
    let remindAt: Date?
    let isEditable: Bool
    let now: Date
    let perform: (InboxMenuAction) -> Void

    /// - Parameters:
    ///   - placement: the list the chat shows in.
    ///   - remindAt: the chat's reminder, if it has one.
    ///   - isEditable: false turns every item off (the stored state cannot
    ///     be written).
    ///   - now: the time the choices count from.
    ///   - perform: runs the chosen item.
    public init(
        placement: InboxPlacement,
        remindAt: Date?,
        isEditable: Bool,
        now: Date = .now,
        perform: @escaping (InboxMenuAction) -> Void
    ) {
        self.placement = placement
        self.remindAt = remindAt
        self.isEditable = isEditable
        self.now = now
        self.perform = perform
    }

    public var body: some View {
        Group {
            if placement == .archived {
                Button { perform(.unarchive) } label: {
                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button { perform(.archive) } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }

            if placement == .snoozed {
                Button { perform(.unsnooze) } label: {
                    Label("Unsnooze", systemImage: "sun.max")
                }
            } else {
                timeMenu(.snooze)
            }

            if remindAt != nil {
                Button { perform(.cancelReminder) } label: {
                    Label("Cancel Reminder", systemImage: "bell.slash")
                }
            } else {
                timeMenu(.remind)
            }
        }
        .disabled(!isEditable)
    }

    private func timeMenu(_ kind: InboxTimeKind) -> some View {
        Menu {
            ForEach(InboxTimeChoice.allCases) { choice in
                if let date = choice.date(now: now) {
                    Button(kind == .snooze ? choice.snoozeTitle : choice.remindTitle) {
                        perform(kind == .snooze ? .snooze(until: date) : .remind(at: date))
                    }
                }
            }
            Divider()
            Button("Pick a Date and Time…") {
                perform(.pickDate(kind))
            }
        } label: {
            if kind == .snooze {
                Label("Snooze", systemImage: "moon.zzz")
            } else {
                Label("Remind Me Later", systemImage: "alarm")
            }
        }
    }
}

/// The sheet behind "Pick a Date and Time…" (MATRIX-207).
public struct InboxDatePickerSheet: View {
    let kind: InboxTimeKind
    let chatName: String
    let pick: (Date) -> Void

    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - kind: a snooze end or a reminder.
    ///   - chatName: the chat, for the title.
    ///   - initial: the time the picker starts at.
    ///   - pick: gets the chosen time. The sheet then closes.
    public init(kind: InboxTimeKind, chatName: String, initial: Date, pick: @escaping (Date) -> Void) {
        self.kind = kind
        self.chatName = chatName
        self.pick = pick
        _date = State(initialValue: initial)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind == .snooze ? "Snooze \(chatName) Until" : "Remind Me About \(chatName)")
                .font(.headline)
                .lineLimit(1)
            DatePicker("Time", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(kind == .snooze ? "Snooze" : "Set Reminder") {
                    pick(date)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

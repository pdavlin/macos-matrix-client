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
            Button("Custom…") {
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

/// The sheet behind "Custom…" (MATRIX-207): a typed time, presets, and a
/// field-style date picker (`TimeChoiceSheet`).
public struct InboxDatePickerSheet: View {
    let kind: InboxTimeKind
    let chatName: String
    let now: Date
    let pick: (Date) -> Void

    /// - Parameters:
    ///   - kind: a snooze end or a reminder.
    ///   - chatName: the chat, for the title.
    ///   - now: the time the choices count from.
    ///   - pick: gets the chosen time. The sheet then closes.
    public init(kind: InboxTimeKind, chatName: String, now: Date = .now, pick: @escaping (Date) -> Void) {
        self.kind = kind
        self.chatName = chatName
        self.now = now
        self.pick = pick
    }

    public var body: some View {
        TimeChoiceSheet(
            title: kind == .snooze ? "Snooze \(chatName) until" : "Remind me about \(chatName)",
            confirmLabel: kind == .snooze ? "Snooze" : "Set Reminder",
            now: now,
            choose: pick
        )
    }
}

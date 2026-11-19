import Foundation

/// The short note a window shows after an inbox action, with its Undo
/// (MATRIX-206): "Archived Alice · Undo".
public struct InboxNotice: Identifiable, Equatable, Sendable {
    /// How long the note stays.
    public static let duration: Duration = .seconds(6)

    /// New for each action, so a second action restarts the timer.
    public let id: UUID
    /// The note's text.
    public var message: String
    /// The states the action replaced, by room ID. Undo writes them back.
    public var undoStates: [String: InboxRoomState]

    public init(id: UUID = UUID(), message: String, undoStates: [String: InboxRoomState]) {
        self.id = id
        self.message = message
        self.undoStates = undoStates
    }

    /// The note after archiving the chat named `chatName`.
    public static func archived(_ chatName: String, undoStates: [String: InboxRoomState]) -> InboxNotice {
        InboxNotice(message: "Archived \(chatName)", undoStates: undoStates)
    }

    /// The note after snoozing a chat (MATRIX-207). `when` is
    /// `InboxTimeText.when(_:now:)`.
    public static func snoozed(_ chatName: String, until when: String, undoStates: [String: InboxRoomState]) -> InboxNotice {
        InboxNotice(message: "Snoozed \(chatName) until \(when)", undoStates: undoStates)
    }

    /// The note after setting a reminder (MATRIX-207).
    public static func reminderSet(_ chatName: String, at when: String, undoStates: [String: InboxRoomState]) -> InboxNotice {
        InboxNotice(message: "Reminder for \(chatName) at \(when)", undoStates: undoStates)
    }
}

/// Which time a date picker or a time menu sets (MATRIX-207).
public enum InboxTimeKind: String, Sendable, Hashable {
    case snooze
    case remind
}

/// One item of a chat's inbox menu (MATRIX-206, MATRIX-207): the row
/// menus and ⌘K share the menu and send these.
public enum InboxMenuAction: Equatable, Sendable {
    case archive
    case unarchive
    case snooze(until: Date)
    case unsnooze
    case remind(at: Date)
    case cancelReminder
    /// "Pick a Date and Time…": opens the date picker.
    case pickDate(InboxTimeKind)
}

/// The date picker for a chosen snooze end or reminder (MATRIX-207).
public struct InboxDatePickerRequest: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var kind: InboxTimeKind
    public var roomIds: [String]
    public var chatName: String

    public init(kind: InboxTimeKind, roomIds: [String], chatName: String) {
        self.kind = kind
        self.roomIds = roomIds
        self.chatName = chatName
    }
}

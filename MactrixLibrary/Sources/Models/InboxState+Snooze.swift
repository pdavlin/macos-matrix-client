import Foundation

// MATRIX-207: Snooze and Remind me later on the inbox-state model of
// MATRIX-206. The storage, the activity rule, and the merged-chat rule are
// in `InboxState.swift`.

public extension InboxStateDocument {
    /// Snoozes the rooms until `until`, set at `time`. An archive ends; a
    /// reminder stays.
    mutating func snooze(_ roomIds: some Sequence<String>, until: Date, at time: Date) {
        update(roomIds) { state in
            state.snoozedUntil = until
            state.snoozedAt = time
            state.archivedAt = nil
        }
    }

    /// Ends the snooze of the rooms: they go back to the Inbox.
    mutating func unsnooze(_ roomIds: some Sequence<String>) {
        update(roomIds) { state in
            state.snoozedUntil = nil
            state.snoozedAt = nil
        }
    }

    /// Sets a reminder on the rooms for `remindAt`, set at `time`. The chat
    /// stays where it is.
    mutating func remind(_ roomIds: some Sequence<String>, at remindAt: Date, setAt time: Date) {
        update(roomIds) { state in
            state.remindAt = remindAt
            state.remindSetAt = time
        }
    }

    /// Drops the reminder of the rooms.
    mutating func cancelReminder(_ roomIds: some Sequence<String>) {
        update(roomIds) { state in
            state.remindAt = nil
            state.remindSetAt = nil
        }
    }

    /// The earliest snooze end or reminder, or nil when there is none. The
    /// timer waits for it.
    var nextDueDate: Date? {
        rooms.values.flatMap { [$0.snoozedUntil, $0.remindAt].compactMap(\.self) }.min()
    }

    /// The chats whose snooze or reminder is due at `now`, one entry per
    /// chat: a merged chat (MATRIX-139) is one chat, named by its merge.
    /// Sorted by room ID, so the order is stable.
    func dueChats(at now: Date, merges: MergedChatDocument) -> [InboxDueChat] {
        var byChat: [String: InboxDueChat] = [:]
        for (roomId, state) in rooms {
            let snoozeEnds = state.snoozedUntil.map { $0 <= now } ?? false
            let reminderFires = state.remindAt.map { $0 <= now } ?? false
            guard snoozeEnds || reminderFires else { continue }
            let merge = merges.merge(containing: roomId)
            let chatId = merge?.id ?? roomId
            var chat = byChat[chatId] ?? InboxDueChat(
                id: chatId,
                roomIds: merge?.rooms ?? [roomId],
                mergedChatName: merge?.name,
                defaultRoomId: merge?.effectiveDefaultRoom ?? roomId
            )
            chat.snoozeEnded = chat.snoozeEnded || snoozeEnds
            chat.reminderFired = chat.reminderFired || reminderFires
            byChat[chatId] = chat
        }
        return byChat.values.sorted { $0.id < $1.id }
    }

    /// Clears what came due in `chats`: a due snooze ends, a due reminder
    /// goes, and the chat of a due reminder leaves the Archived list. Each
    /// field is cleared only when it is still due at `now`, so a newer
    /// snooze or reminder that another device set stays.
    mutating func resolve(_ chats: [InboxDueChat], at now: Date) {
        for chat in chats {
            update(chat.roomIds) { state in
                if chat.snoozeEnded, let until = state.snoozedUntil, until <= now {
                    state.snoozedUntil = nil
                    state.snoozedAt = nil
                }
                if chat.reminderFired, let remindAt = state.remindAt, remindAt <= now {
                    state.remindAt = nil
                    state.remindSetAt = nil
                    state.archivedAt = nil
                }
            }
        }
    }

    /// The snooze end of the chat that holds `roomId`: the latest end over
    /// a merged chat's members.
    func snoozedUntil(of roomId: String, merges: MergedChatDocument) -> Date? {
        let ids = Self.chatRoomIds(for: [roomId], merges: merges)
        return ids.compactMap { state(of: $0).snoozedUntil }.max()
    }

    /// The reminder time of the chat that holds `roomId`: the earliest over
    /// a merged chat's members.
    func remindAt(of roomId: String, merges: MergedChatDocument) -> Date? {
        let ids = Self.chatRoomIds(for: [roomId], merges: merges)
        return ids.compactMap { state(of: $0).remindAt }.min()
    }

    /// The mark a chat search row shows for the chat that holds `roomId`:
    /// "Archived", "Snoozed until …", or nil for a chat in the Inbox. The
    /// ⌘K quick switcher (MATRIX-206, MATRIX-207) and the iOS chat search
    /// (MATRIX-248) show it. A merged chat is one chat.
    func searchMark(of roomId: String, merges: MergedChatDocument, now: Date) -> String? {
        switch placement(of: roomId, merges: merges) {
        case .archived:
            "Archived"
        case .snoozed:
            snoozedUntil(of: roomId, merges: merges).map { InboxTimeText.snoozed(until: $0, now: now) }
        case .inbox:
            nil
        }
    }
}

public extension VisibleChatList where Room == ChatListItem {
    /// The list with "Snoozed until …" in place of each chat's preview
    /// (MATRIX-207), for the Snoozed list filter.
    func withSnoozeNotes(inbox: InboxStateDocument, merges: MergedChatDocument, now: Date) -> VisibleChatList<ChatListItem> {
        func noted(_ item: ChatListItem) -> ChatListItem {
            guard let roomId = item.roomIds.first, let until = inbox.snoozedUntil(of: roomId, merges: merges) else {
                return item
            }
            let note = InboxTimeText.snoozed(until: until, now: now)
            switch item {
            case var .room(entry):
                entry.row.inboxNote = note
                return .room(entry)
            case var .merged(merged):
                merged.row.inboxNote = note
                return .merged(merged)
            }
        }
        return VisibleChatList(favorites: favorites.map(noted), list: list.map(noted))
    }
}

/// One chat whose snooze or reminder came due (MATRIX-207).
public struct InboxDueChat: Equatable, Sendable, Identifiable {
    /// The room ID, or the merged chat's ID.
    public var id: String
    /// The rooms to mark unread: one room, or every member.
    public var roomIds: [String]
    /// The merged chat's name, when the chat is one.
    public var mergedChatName: String?
    /// The room a click on the notification opens.
    public var defaultRoomId: String
    /// The snooze ended: the chat is back in the Inbox.
    public var snoozeEnded = false
    /// The reminder fired.
    public var reminderFired = false

    public init(
        id: String,
        roomIds: [String],
        mergedChatName: String? = nil,
        defaultRoomId: String,
        snoozeEnded: Bool = false,
        reminderFired: Bool = false
    ) {
        self.id = id
        self.roomIds = roomIds
        self.mergedChatName = mergedChatName
        self.defaultRoomId = defaultRoomId
        self.snoozeEnded = snoozeEnded
        self.reminderFired = reminderFired
    }

    /// The local notification for the chat named `chatName`: "Reminder:
    /// <chat>" for a reminder, else the chat's name with "Snooze ended".
    public func notification(chatName: String) -> (title: String, body: String) {
        if reminderFired {
            return ("Reminder: \(chatName)", "You asked to be reminded about this chat.")
        }
        return (chatName, "Snooze ended.")
    }
}

/// The time choices of Snooze and Remind me later (MATRIX-207).
public enum InboxTimeChoice: String, CaseIterable, Sendable, Identifiable {
    case oneHour
    case thisEvening
    case tomorrow
    case nextWeek

    public var id: Self { self }

    /// The hour "this evening" means.
    static let eveningHour = 18
    /// The hour "tomorrow" and "next week" mean.
    static let morningHour = 9

    /// The time this choice means at `now`, or nil when it has passed:
    /// "this evening" (18:00) after 18:00.
    /// - "tomorrow" is 09:00 the next day.
    /// - "next week" is 09:00 on the next Monday after today.
    public func date(now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .oneHour:
            return now.addingTimeInterval(3600)
        case .thisEvening:
            guard let evening = calendar.date(bySettingHour: Self.eveningHour, minute: 0, second: 0, of: now),
                  evening > now
            else { return nil }
            return evening
        case .tomorrow:
            guard let day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
            return calendar.date(bySettingHour: Self.morningHour, minute: 0, second: 0, of: day)
        case .nextWeek:
            let monday = DateComponents(hour: Self.morningHour, minute: 0, second: 0, weekday: 2)
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            return calendar.nextDate(
                after: startOfTomorrow.addingTimeInterval(-1),
                matching: monday,
                matchingPolicy: .nextTime
            )
        }
    }

    /// The menu item under "Snooze".
    public var snoozeTitle: String {
        switch self {
        case .oneHour: "For 1 Hour"
        case .thisEvening: "Until This Evening"
        case .tomorrow: "Until Tomorrow"
        case .nextWeek: "Until Next Week"
        }
    }

    /// The menu item under "Remind Me Later".
    public var remindTitle: String {
        switch self {
        case .oneHour: "In 1 Hour"
        case .thisEvening: "This Evening"
        case .tomorrow: "Tomorrow"
        case .nextWeek: "Next Week"
        }
    }
}

/// The words for a snooze end or a reminder time (MATRIX-207).
public enum InboxTimeText {
    /// "6:00 PM" today, "tomorrow 9:00 AM", "Mon 9:00 AM" within a week,
    /// else "Nov 30, 9:00 AM".
    public static func when(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = formatted(date, template: "jmm", calendar: calendar, locale: locale)
        if calendar.isDate(date, inSameDayAs: now) {
            return time
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow \(time)"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if days > 0, days < 7 {
            return "\(formatted(date, template: "EEE", calendar: calendar, locale: locale)) \(time)"
        }
        return formatted(date, template: "MMMd jmm", calendar: calendar, locale: locale)
    }

    /// The chat-list note of a snoozed chat: "Snoozed until tomorrow 9:00 AM".
    public static func snoozed(until date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        "Snoozed until \(when(date, now: now, calendar: calendar, locale: locale))"
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

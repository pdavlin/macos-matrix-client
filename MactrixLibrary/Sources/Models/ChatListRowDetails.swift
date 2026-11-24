import Foundation

// MATRIX-224: the draft and typing states of a chat-list row, and the
// Unanswered and Drafts list filters applied to the visible list.

/// The kind of a saved composer draft, as the chat list reads it.
public enum ChatListDraftKind: Equatable, Sendable {
    case newMessage
    case reply
    /// An edit of a sent message. The row does not show it as a draft.
    case edit
}

/// The draft text a chat-list row shows after "Draft:".
public enum ChatListDraftText {
    /// The row text of a saved draft, or nil when the row shows no draft.
    ///
    /// Mention chips (`matrix.to` pill links) read as "@label", and the
    /// lines join into one, as the preview of a message does.
    ///
    /// - Parameters:
    ///   - draftText: the draft's plain text (`MentionMarkdown` draft text).
    ///   - kind: the draft's kind. An edit gives nil: its text is a change
    ///     to a sent message, not an unsent message.
    /// - Returns: nil for an edit and for a draft with no visible text (a
    ///   reply with an empty composer).
    public static func previewText(draftText: String, kind: ChatListDraftKind) -> String? {
        guard kind != .edit else { return nil }
        let plain = MentionMarkdown.plainText(for: MentionMarkdown.segments(fromDraftText: draftText))
        return ChatListLatestEvent.collapse(plain)
    }
}

/// The typing state of a chat-list row.
public enum ChatListTypingText {
    /// The row text while people type, or nil when nobody types.
    ///
    /// A direct chat reads "typing…": the title names the person, as the
    /// preview leaves out their name. A group names one or two people, and
    /// counts the others after the first.
    ///
    /// - Parameters:
    ///   - names: the display names of the people who type, without the
    ///     user, in the SDK's order.
    ///   - isDirect: the chat is a direct chat.
    public static func text(names: [String], isDirect: Bool) -> String? {
        guard let first = names.first else { return nil }
        if isDirect {
            return "typing…"
        }
        switch names.count {
        case 1:
            return "\(first) is typing…"
        case 2:
            return "\(first) and \(names[1]) are typing…"
        default:
            return "\(first) and \(names.count - 1) others are typing…"
        }
    }
}

/// What the second line of a chat-list row shows.
///
/// Order: MATRIX-207's inbox note, then the typing state, then the draft,
/// then the latest event's preview. Typing is live and short, so it goes
/// before the draft; the note is why the Snoozed filter shows the chat.
public enum ChatListPreviewLine: Equatable, Sendable {
    case inboxNote(String)
    case typing(String)
    /// The draft text, without the prefix.
    case draft(String)
    case preview(String?)

    /// The prefix before a draft's text.
    public static let draftPrefix = "Draft:"

    /// The line as plain text, for VoiceOver.
    public var spokenText: String {
        switch self {
        case let .inboxNote(text), let .typing(text):
            text
        case let .draft(text):
            "\(Self.draftPrefix) \(text)"
        case let .preview(text):
            text ?? ""
        }
    }
}

public extension ChatListRowModel {
    /// The second line of the row. See `ChatListPreviewLine`.
    var previewLine: ChatListPreviewLine {
        if let inboxNote {
            return .inboxNote(inboxNote)
        }
        if let typing = ChatListTypingText.text(names: typingNames, isDirect: isDirect) {
            return .typing(typing)
        }
        if let draft {
            return .draft(draft)
        }
        return .preview(preview)
    }
}

/// The saved drafts the chat list knows, as row text.
///
/// A room's draft is its SDK draft of the main timeline. A merged chat's
/// draft is the merged composer's draft, which lives in memory for the
/// session (MATRIX-143); a member room's SDK draft does not show on the
/// merged row, because the merged composer does not load it.
public struct ChatListDrafts: Equatable, Sendable {
    /// Row text by room ID.
    public var rooms: [String: String]
    /// Row text by merged chat ID.
    public var merges: [String: String]

    public init(rooms: [String: String] = [:], merges: [String: String] = [:]) {
        self.rooms = rooms
        self.merges = merges
    }

    /// The rooms the Drafts filter narrows the SDK list to: each room with
    /// a draft, and every member of a merged chat with a draft.
    public func roomIds(merges document: MergedChatDocument) -> Set<String> {
        var ids = Set(rooms.keys)
        for merge in document.merges where merges[merge.id] != nil {
            ids.formUnion(merge.rooms)
        }
        return ids
    }
}

public extension ChatListItem {
    /// The chat waits for an answer (`ChatListUnanswered`). A merged chat
    /// reads its newest member.
    var isUnanswered: Bool {
        switch self {
        case let .room(entry): entry.isUnanswered
        case let .merged(merged): merged.isUnanswered
        }
    }
}

public extension VisibleChatList where Room == ChatListItem {
    /// The list with each chat's draft on its row. A merged chat takes the
    /// merged composer's draft only (`ChatListDrafts`).
    func withDrafts(_ drafts: ChatListDrafts) -> VisibleChatList<ChatListItem> {
        guard !drafts.rooms.isEmpty || !drafts.merges.isEmpty else { return self }
        func drafted(_ item: ChatListItem) -> ChatListItem {
            switch item {
            case var .room(entry):
                entry.row.draft = drafts.rooms[entry.id]
                return .room(entry)
            case var .merged(merged):
                merged.row.draft = drafts.merges[merged.id]
                return .merged(merged)
            }
        }
        return VisibleChatList(favorites: favorites.map(drafted), list: list.map(drafted))
    }

    /// The list with the names of the people who type on each row. A
    /// merged chat shows the people of every member, each one time, in
    /// member order.
    ///
    /// - Parameter names: the names by room ID, for the rooms where someone
    ///   types.
    func withTyping(_ names: [String: [String]]) -> VisibleChatList<ChatListItem> {
        guard !names.isEmpty else { return self }
        func typing(_ item: ChatListItem) -> ChatListItem {
            var seen = Set<String>()
            let typing = item.roomIds.flatMap { names[$0] ?? [] }.filter { seen.insert($0).inserted }
            guard !typing.isEmpty else { return item }
            switch item {
            case var .room(entry):
                entry.row.typingNames = typing
                return .room(entry)
            case var .merged(merged):
                merged.row.typingNames = typing
                return .merged(merged)
            }
        }
        return VisibleChatList(favorites: favorites.map(typing), list: list.map(typing))
    }

    /// The chats the list filter keeps that the SDK cannot pick: the
    /// unanswered chats for Unanswered, the chats with a draft on their row
    /// for Drafts (call `withDrafts(_:)` first). Every other filter keeps
    /// the list.
    func filtered(for filter: ChatListFilter) -> VisibleChatList<ChatListItem> {
        let keep: (ChatListItem) -> Bool
        switch filter {
        case .unanswered:
            keep = \.isUnanswered
        case .drafts:
            keep = { $0.row.draft != nil }
        case .inbox, .unread, .people, .groups, .lowPriority, .archived, .snoozed:
            return self
        }
        return VisibleChatList(favorites: favorites.filter(keep), list: list.filter(keep))
    }
}

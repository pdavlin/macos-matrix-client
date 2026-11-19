import Foundation

/// One row of the Bookmarks list (MATRIX-208): what the stored bookmark
/// names, and what the SDK read about it when the list showed.
public struct BookmarkListRow: Equatable, Sendable, Identifiable {
    /// The room of a bookmark, as the SDK knows it now.
    public struct Room: Equatable, Sendable {
        public var title: String
        public var avatarUrl: String?
        public var initials: ChatListInitials

        public init(title: String, avatarUrl: String?, initials: ChatListInitials) {
            self.title = title
            self.avatarUrl = avatarUrl
            self.initials = initials
        }

        /// A room the account does not have any more: the room ID is the
        /// title.
        public static func unknown(roomId: String) -> Room {
            Room(title: roomId, avatarUrl: nil, initials: .room(title: roomId, roomId: roomId))
        }
    }

    /// The bookmarked message, read through the SDK. Nothing of it is
    /// stored.
    public struct Message: Equatable, Sendable {
        public var senderName: String
        /// One line. Empty for an event with nothing to show.
        public var preview: String
        public var date: Date

        public init(senderName: String, preview: String, date: Date) {
            self.senderName = senderName
            self.preview = preview
            self.date = date
        }
    }

    public enum Content: Equatable, Sendable {
        /// The SDK read has not finished.
        case loading
        case message(Message)
        /// The event did not load: deleted from the server's view, a room
        /// the account left, or no network. The row says "Message not
        /// available" and offers Remove.
        case unavailable
    }

    public var bookmark: Bookmark
    public var room: Room
    public var content: Content

    public var id: BookmarkKey { bookmark.key }

    public init(bookmark: Bookmark, room: Room, content: Content) {
        self.bookmark = bookmark
        self.room = room
        self.content = content
    }

    /// The rows for `document`, newest saved first (MATRIX-208).
    ///
    /// - Parameters:
    ///   - document: The account's bookmarks.
    ///   - rooms: The rooms the SDK knows, by room ID.
    ///   - messages: The SDK reads that finished, by key. A nil value is a
    ///     read that failed.
    public static func rows(
        for document: BookmarkDocument,
        rooms: [String: Room],
        messages: [BookmarkKey: Message?]
    ) -> [BookmarkListRow] {
        document.newestFirst.map { bookmark in
            let content: Content = switch messages[bookmark.key] {
            case .none: .loading
            case .some(.none): .unavailable
            case let .some(.some(message)): .message(message)
            }
            return BookmarkListRow(
                bookmark: bookmark,
                room: rooms[bookmark.roomId] ?? .unknown(roomId: bookmark.roomId),
                content: content
            )
        }
    }

    /// The one-line preview of a message body, without a sender prefix:
    /// the row shows the sender on its own. The chat list's wording
    /// (`ChatListLatestEvent`), so a photo reads "Photo" in both places.
    public static func preview(of content: ChatListPreviewContent, senderId: String, senderName: String?) -> String {
        // A direct chat's row from another sender takes no prefix.
        let event = ChatListLatestEvent(
            timestamp: .distantPast,
            sender: ChatListSender(userId: senderId, displayName: senderName, isOwn: false),
            content: content
        )
        return event.preview(isDirect: true).text ?? ""
    }
}

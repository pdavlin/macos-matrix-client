import Foundation

/// One message of a thread-list row (MATRIX-200): the thread root or the
/// latest reply, as the SDK's `ThreadListItemEvent` gives it.
public struct ThreadListMessage: Equatable, Sendable {
    public let eventId: String
    public let sender: ChatListSender
    public let avatarUrl: String?
    public let date: Date
    /// The content, or nil when the SDK does not give it.
    public let content: ChatListPreviewContent?

    public init(eventId: String, sender: ChatListSender, avatarUrl: String?, date: Date, content: ChatListPreviewContent?) {
        self.eventId = eventId
        self.sender = sender
        self.avatarUrl = avatarUrl
        self.date = date
        self.content = content
    }

    /// The sender, as the avatar views take a profile.
    public var senderProfile: ThreadReplier {
        ThreadReplier(userId: sender.userId, displayName: sender.displayName, avatarUrl: avatarUrl)
    }

    /// The text of the message with no sender prefix, for the root excerpt.
    /// Nil when the content is not known or has no text line.
    public var excerpt: String? {
        line(prefixed: false)
    }

    /// The text of the message with "You: " or "Name: " before it, for the
    /// latest reply line. Emotes and membership lines name the sender in the
    /// text itself.
    public var prefixedExcerpt: String? {
        line(prefixed: true)
    }

    private func line(prefixed: Bool) -> String? {
        guard let content else { return nil }
        // The chat list's wording rules: a direct chat drops the "Name: "
        // prefix, and "You: " goes away with `isOwn` false.
        let speaker = prefixed ? sender : ChatListSender(userId: sender.userId, displayName: sender.displayName, isOwn: false)
        let event = ChatListLatestEvent(timestamp: date, sender: speaker, content: content, hasSendFailure: false)
        return event.preview(isDirect: !prefixed).text
    }
}

/// One row of the room's thread list (MATRIX-200), from the SDK's
/// `ThreadListItem`.
public struct ThreadListEntry: Identifiable, Equatable, Sendable {
    public let root: ThreadListMessage
    /// The most recent reply, when the SDK gives it.
    public let latestReply: ThreadListMessage?
    /// Replies in the thread, the root not counted.
    public let replyCount: Int

    public init(root: ThreadListMessage, latestReply: ThreadListMessage?, replyCount: Int) {
        self.root = root
        self.latestReply = latestReply
        self.replyCount = replyCount
    }

    /// The thread root's event ID. It opens the thread panel.
    public var id: String {
        root.eventId
    }

    /// The time the row shows: the latest reply's, else the root's.
    public var lastActivity: Date {
        latestReply?.date ?? root.date
    }
}

/// A change to an observable list, as the SDK states it (MATRIX-200).
///
/// The platform-neutral twin of the SDK's `ThreadListUpdate`, which mirrors
/// `eyeball_im::VectorDiff`. The SDK decides the order and every change; the
/// app only replays the changes in order (hard rule 1).
public enum ListDiff<Element> {
    case append([Element])
    case clear
    case pushFront(Element)
    case pushBack(Element)
    case popFront
    case popBack
    case insert(index: Int, value: Element)
    case set(index: Int, value: Element)
    case remove(index: Int)
    case truncate(length: Int)
    case reset([Element])

    /// The same change with each element transformed.
    public func map<T>(_ transform: (Element) -> T) -> ListDiff<T> {
        switch self {
        case let .append(values): .append(values.map(transform))
        case .clear: .clear
        case let .pushFront(value): .pushFront(transform(value))
        case let .pushBack(value): .pushBack(transform(value))
        case .popFront: .popFront
        case .popBack: .popBack
        case let .insert(index, value): .insert(index: index, value: transform(value))
        case let .set(index, value): .set(index: index, value: transform(value))
        case let .remove(index): .remove(index: index)
        case let .truncate(length): .truncate(length: length)
        case let .reset(values): .reset(values.map(transform))
        }
    }
}

public extension Array {
    /// Applies one SDK list change.
    ///
    /// - Returns: false, with the array not changed, when the change does
    ///   not fit the array (an index out of range, a pop on an empty
    ///   array). The caller then takes a new snapshot from the SDK.
    @discardableResult
    mutating func apply(_ diff: ListDiff<Element>) -> Bool {
        switch diff {
        case let .append(values):
            append(contentsOf: values)
        case .clear:
            removeAll()
        case let .pushFront(value):
            insert(value, at: 0)
        case let .pushBack(value):
            append(value)
        case .popFront:
            guard !isEmpty else { return false }
            removeFirst()
        case .popBack:
            guard !isEmpty else { return false }
            removeLast()
        case let .insert(index, value):
            guard (0 ... count).contains(index) else { return false }
            insert(value, at: index)
        case let .set(index, value):
            guard indices.contains(index) else { return false }
            self[index] = value
        case let .remove(index):
            guard indices.contains(index) else { return false }
            remove(at: index)
        case let .truncate(length):
            guard length >= 0 else { return false }
            if length < count {
                removeSubrange(length...)
            }
        case let .reset(values):
            self = values
        }
        return true
    }
}

/// The pagination state of the thread list, as the SDK's
/// `ThreadListPaginationState` gives it (MATRIX-200).
public enum ThreadListPagination: Equatable, Sendable {
    /// No page loads. `endReached` is true when no more pages exist.
    case idle(endReached: Bool)
    /// A page loads.
    case loading
}

/// What the end of a non-empty thread list shows (MATRIX-200).
public enum ThreadListFooter: Equatable, Sendable {
    /// More pages exist: a loading row. Its appearance asks for the next
    /// page.
    case loading
    /// The last page failed: the message and Retry.
    case failed(String)
    /// No more pages: nothing.
    case end
}

/// What the Threads pane shows (MATRIX-200).
public enum ThreadListPaneContent: Equatable, Sendable {
    /// No rows yet and the first page loads, or is about to.
    case loading
    /// The list ended with no rows: "No threads in this room".
    case empty
    /// No rows and the page failed: the message and Retry.
    case failed(String)
    /// The rows, with a footer.
    case list(footer: ThreadListFooter)

    /// The empty-state text.
    public static let emptyText = "No threads in this room"

    /// The error title.
    public static let failedTitle = "Could not load threads"

    /// - Parameters:
    ///   - entryCount: the rows the list holds.
    ///   - pagination: the SDK's last pagination state.
    ///   - errorMessage: the error of the last page request, or nil.
    public static func of(entryCount: Int, pagination: ThreadListPagination, errorMessage: String?) -> ThreadListPaneContent {
        if entryCount == 0 {
            if let errorMessage {
                return .failed(errorMessage)
            }
            return pagination == .idle(endReached: true) ? .empty : .loading
        }
        if let errorMessage {
            return .list(footer: .failed(errorMessage))
        }
        return .list(footer: pagination == .idle(endReached: true) ? .end : .loading)
    }
}

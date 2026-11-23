import Foundation

/// How the user opened a chat (MATRIX-188). It decides whether the chat's
/// composer takes the keyboard focus: `asksForComposerFocus`.
public enum ChatOpenSource: Equatable, Sendable {
    /// A click on a chat-list row or on a pinned tile.
    case click
    /// A chat-list selection change by the keyboard: the arrow keys, or a
    /// type-select. The focus stays in the list, so the next arrow key
    /// moves on.
    case listKeyboard
    /// Return on the selected chat-list row.
    case returnKey
    /// A pick in the ⌘K quick switcher.
    case quickSwitcher
    /// The chat a New Chat draft opens.
    case newChat
    /// A click on a message notification.
    case notification
    /// A Go-menu command: ⌘] or ⌘[ (MATRIX-217).
    case shortcut
    /// A click on a Matrix link in a message body (MATRIX-203).
    case link
    /// The next chat after Archive, Snooze, or Mark as Read on the open
    /// chat (MATRIX-222).
    case inboxFlow
    /// A chat-list selection change with no known input event.
    case unknown

    /// Whether this way of opening a chat moves the keyboard focus to the
    /// chat's composer.
    public var asksForComposerFocus: Bool {
        switch self {
        case .click, .returnKey, .quickSwitcher, .newChat, .notification, .shortcut, .link, .inboxFlow: true
        case .listKeyboard, .unknown: false
        }
    }

    /// The source of a chat-list selection change: the list does not tell a
    /// click from an arrow key, the input event does.
    public init(listSelectionEvent event: ListSelectionEvent) {
        switch event {
        case .pointer: self = .click
        case .keyboard: self = .listKeyboard
        case .other: self = .unknown
        }
    }
}

/// The kind of input event that changed a chat-list selection (MATRIX-188).
public enum ListSelectionEvent: Equatable, Sendable {
    /// A mouse or trackpad click.
    case pointer
    /// A key press.
    case keyboard
    /// No event, or an event of another kind.
    case other
}

/// A request for the composer of one chat to take the keyboard focus
/// (MATRIX-188). The window keeps at most one; the composer of `chat` takes
/// it when the chat can take a message.
public struct ComposerFocusRequest: Equatable, Sendable {
    /// The chat whose composer takes the focus.
    public let chat: ChatSelection
    /// The thread whose panel composer takes the focus, or nil for the
    /// chat's main composer (MATRIX-216). A room shows two composers while
    /// its thread panel is open.
    public let threadRoot: String?
    /// Tells two requests for the same chat apart, so a second Return on
    /// the same row is a new request.
    public let serial: Int

    public init(chat: ChatSelection, threadRoot: String? = nil, serial: Int) {
        self.chat = chat
        self.threadRoot = threadRoot
        self.serial = serial
    }
}

/// The rule for which way of opening a chat moves the keyboard focus to its
/// composer (MATRIX-188).
public enum ComposerFocusRule {
    /// The request that opening `chat` from `source` makes. Nil when the
    /// source does not ask for focus or no chat opens: a new selection then
    /// drops an older request, so the request never moves the focus later
    /// for a chat the user left.
    public static func request(
        opening chat: ChatSelection?,
        from source: ChatOpenSource,
        serial: Int
    ) -> ComposerFocusRequest? {
        guard let chat, source.asksForComposerFocus else { return nil }
        return ComposerFocusRequest(chat: chat, serial: serial)
    }

    /// The request that "Reply in Thread" makes (MATRIX-216): the composer
    /// of the thread panel on `root` takes the focus, so the reply the user
    /// types goes into the thread and not into the main composer.
    public static func request(replyingInThreadOf root: String, inRoom roomId: String, serial: Int) -> ComposerFocusRequest {
        ComposerFocusRequest(chat: .room(roomId), threadRoot: root, serial: serial)
    }

    /// Whether a chat with this membership can take a message. A left,
    /// invited, knocked, or banned room has no composer to focus.
    public static func canTakeMessage(_ membership: Membership) -> Bool {
        membership == .joined
    }

    /// Whether the composer of `composerChat` takes `request`: the request
    /// is for this chat and this composer of it, and the chat can take a
    /// message. Otherwise the focus stays where it is.
    ///
    /// - Parameters:
    ///   - threadRoot: the thread root of the composer's timeline (the
    ///     thread panel's composer), or nil for the chat's main composer.
    ///   - membership: the membership of the room the composer sends to (in
    ///     a merged chat, the send target).
    public static func composer(
        of composerChat: ChatSelection,
        threadRoot: String? = nil,
        membership: Membership,
        takes request: ComposerFocusRequest?
    ) -> Bool {
        guard let request, request.chat == composerChat, request.threadRoot == threadRoot else { return false }
        return canTakeMessage(membership)
    }
}

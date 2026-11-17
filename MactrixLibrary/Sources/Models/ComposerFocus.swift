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
    /// A Go-menu command: ⌘1…⌘9, ⇧⌘] or ⇧⌘[.
    case shortcut
    /// A chat-list selection change with no known input event.
    case unknown

    /// Whether this way of opening a chat moves the keyboard focus to the
    /// chat's composer.
    public var asksForComposerFocus: Bool {
        switch self {
        case .click, .returnKey, .quickSwitcher, .newChat, .notification, .shortcut: true
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
    /// Tells two requests for the same chat apart, so a second Return on
    /// the same row is a new request.
    public let serial: Int

    public init(chat: ChatSelection, serial: Int) {
        self.chat = chat
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

    /// Whether a chat with this membership can take a message. A left,
    /// invited, knocked, or banned room has no composer to focus.
    public static func canTakeMessage(_ membership: Membership) -> Bool {
        membership == .joined
    }

    /// Whether the composer of `composerChat` takes `request`: the request
    /// is for this chat, and the chat can take a message. Otherwise the
    /// focus stays where it is.
    ///
    /// - Parameter membership: the membership of the room the composer
    ///   sends to (in a merged chat, the send target).
    public static func composer(
        of composerChat: ChatSelection,
        membership: Membership,
        takes request: ComposerFocusRequest?
    ) -> Bool {
        guard let request, request.chat == composerChat else { return false }
        return canTakeMessage(membership)
    }
}

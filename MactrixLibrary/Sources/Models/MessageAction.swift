import Foundation

/// One thing a person can do to a timeline message (MATRIX-108, M2-B1).
///
/// One model drives three surfaces: the right-click menu on a message row,
/// the hover row, and the Edit-menu section for the targeted message.
/// `MessageActionModel` decides which actions a message offers and whether
/// each one is enabled. The surfaces only draw the result and hand the chosen
/// action back to the row, which makes the SDK call.
///
/// Extension points for the rest of Cluster B. Each story adds its case here,
/// one rule in `MessageActionModel.availability(of:for:)`, its place in
/// `MessageActionModel.order(on:)`, a title and icon in
/// `UI.MessageActionPresentation`, and a handler in the app's
/// `ChatMessageView.perform(_:)`. The exhaustive switches make the compiler
/// list every place a new case must go.
/// - B2 `edit`: own, editable, sent text messages. Section `.modify`.
/// - B3 `redact`: own messages, or others' with the power level. Section
///   `.destructive`.
/// - B5 `forward`: text and media with an event ID. Section `.modify`.
/// - B6 `select`: every message. Section `.organize`.
public enum MessageAction: Hashable, Sendable {
    /// Reply to the message in the composer.
    case reply
    /// Open the message's thread. Hover row only: thread work is deferred
    /// (contract §11), so this keeps its pre-M2 reach and gets no new surface.
    case replyInThread
    /// Toggle one of the quick reactions. Menus group these in a React submenu.
    case toggleReaction(key: String)
    /// Open the reaction picker popover (MATRIX-111, D-3). The hover row,
    /// the right-click menu, and the Edit menu all offer it.
    case openReactionPicker
    /// Copy the message's plain text body or media caption.
    case copyText
    /// Copy the message's matrix.to permalink.
    case copyLink
    /// Pin the message in the room.
    case pin
    /// Unpin the message.
    case unpin
    /// Open the media in Quick Look.
    case quickLook
    /// Play a video inside the row (S-38). A click on the video opens Quick
    /// Look, so inline playback lives in the menu.
    case playInline
    /// Save the media file to the Downloads folder.
    case saveToDownloads

    /// Whether this is one of the quick reactions, which menus fold into one
    /// React submenu and the hover row draws as emoji.
    public var isQuickReaction: Bool {
        if case .toggleReaction = self { return true }
        return false
    }

    /// Whether the media view, not the row, performs this action.
    ///
    /// Media actions need the media view's own state (the downloaded file, the
    /// Quick Look binding, the inline player), so only the menu over the media
    /// offers them. The row menu and the Edit menu leave them out.
    public var isMediaAction: Bool {
        switch self {
        case .quickLook, .playInline, .saveToDownloads:
            return true
        case .reply, .replyInThread, .toggleReaction, .openReactionPicker, .copyText, .copyLink, .pin, .unpin:
            return false
        }
    }
}

/// Where the actions show.
public enum MessageActionSurface: Hashable, Sendable, CaseIterable {
    /// The right-click menu on a message row or on its media.
    case contextMenu
    /// The row of buttons that shows while the pointer is over a message.
    case hoverRow
    /// The message section of the app's Edit menu.
    case editMenu
}

/// Groups of actions. Menus draw a separator between two groups.
///
/// The raw value is the display order. B2 and B5 add `.modify` after
/// `.respond`; B3 adds `.destructive` last.
public enum MessageActionSection: Int, Hashable, Sendable, Comparable {
    case respond
    case media
    case copy
    case organize

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The facts about one message that the action model reads.
///
/// Plain values only, so the model needs no SDK types and runs in unit tests.
/// `Core` builds this from an SDK event (`MessageActionSubject(event:msg:pinnedEventIds:)`).
public struct MessageActionSubject: Equatable, Sendable {
    /// What the message shows, as far as the actions care.
    public enum Content: Equatable, Sendable {
        /// Text, notice, emote, location, and other text-like bodies.
        case text
        case image
        /// A video. `isPlayingInline` is true while the row plays it, which
        /// swaps "Play Inline" for "Quick Look" (S-38).
        case video(isPlayingInline: Bool)
        case audio
        case file
        /// A redacted message. Only Copy Link applies.
        case redacted
        /// Stickers, polls, undecryptable messages, custom events.
        case other

        /// Whether the content is a downloadable media file.
        public var isMedia: Bool {
            switch self {
            case .image, .video, .audio, .file:
                return true
            case .text, .redacted, .other:
                return false
            }
        }
    }

    public var content: Content
    /// Whether the signed-in account sent the message. B2 (edit) and B3
    /// (redact) read it.
    public var isOwn: Bool
    /// The event ID, or nil while the message is a local echo that has only a
    /// transaction ID. Copy Link and Pin need an event ID.
    public var eventId: String?
    /// The SDK's `canBeRepliedTo`. False for a local echo.
    public var canBeRepliedTo: Bool
    /// Whether the room's pinned event list holds this event.
    public var isPinned: Bool
    /// The text Copy Text puts on the pasteboard: the plain body, or the
    /// caption of a media message. Nil or empty means there is no text.
    public var copyableText: String?

    public init(
        content: Content,
        isOwn: Bool,
        eventId: String?,
        canBeRepliedTo: Bool,
        isPinned: Bool,
        copyableText: String?
    ) {
        self.content = content
        self.isOwn = isOwn
        self.eventId = eventId
        self.canBeRepliedTo = canBeRepliedTo
        self.isPinned = isPinned
        self.copyableText = copyableText
    }

    /// The same subject with other content. A video view uses it to report
    /// whether it plays inline.
    public func with(content: Content) -> Self {
        var copy = self
        copy.content = content
        return copy
    }
}

/// One action as a surface draws it.
public struct MessageActionItem: Hashable, Sendable, Identifiable {
    public let action: MessageAction
    public let section: MessageActionSection
    public let isEnabled: Bool

    public var id: MessageAction { action }

    public init(action: MessageAction, section: MessageActionSection, isEnabled: Bool) {
        self.action = action
        self.section = section
        self.isEnabled = isEnabled
    }
}

/// Decides which actions a message offers on each surface (MATRIX-108).
///
/// Every action gets one of three answers for a message:
/// - available: it can run now;
/// - unavailable: it applies to this message but cannot run now, for example
///   Copy Link on a local echo that has no event ID yet;
/// - not applicable: it never applies, for example Quick Look on text.
///
/// Each surface turns that answer into its own policy:
/// - context menu: leaves out "not applicable", shows "unavailable" disabled;
/// - hover row: shows "available" only, so the row stays compact;
/// - Edit menu: always shows the same list, so items do not jump; anything
///   not available is disabled. With no target message, all are disabled.
///
/// Usage:
/// ```swift
/// let items = MessageActionModel.items(for: subject, on: .contextMenu)
/// ```
public enum MessageActionModel {
    /// The quick reactions when the account has no recent emoji yet: the
    /// three fixed emoji from before M2.
    public static let defaultQuickReactionKeys = ["👍", "🎉", "❤️"]

    /// How many quick reactions the hover row and the React submenus show.
    public static let quickReactionCount = 3

    /// The quick reactions for a recent-emoji list (MATRIX-111, D-3): the
    /// top three recent emoji. With fewer than three recents, the defaults
    /// fill the free places, so the hover row keeps its width. With no
    /// recents, the result is `defaultQuickReactionKeys`.
    ///
    /// - Parameter recents: The recent emoji, most recent first.
    /// - Returns: `quickReactionCount` distinct emoji.
    public static func quickReactionKeys(fromRecents recents: [String]) -> [String] {
        var keys: [String] = []
        for emoji in recents + defaultQuickReactionKeys where !emoji.isEmpty && !keys.contains(emoji) {
            keys.append(emoji)
            if keys.count == quickReactionCount { break }
        }
        return keys
    }

    /// The ordered actions for `subject` on `surface`.
    ///
    /// - Parameters:
    ///   - subject: The message, or nil when no message is targeted (only the
    ///     Edit menu has that case; it then shows its list disabled).
    ///   - surface: Where the actions show.
    ///   - quickReactionKeys: The quick reactions, from
    ///     `quickReactionKeys(fromRecents:)`.
    /// - Returns: The actions in display order, each with its enabled state.
    public static func items(
        for subject: MessageActionSubject?,
        on surface: MessageActionSurface,
        quickReactionKeys keys: [String] = defaultQuickReactionKeys
    ) -> [MessageActionItem] {
        order(on: surface, for: subject, quickReactionKeys: keys).compactMap { action in
            let state: Availability = subject.map { Self.availability(of: action, for: $0) } ?? .unavailable
            let shows = switch surface {
            case .contextMenu: state != .notApplicable
            case .hoverRow: state == .available
            case .editMenu: true
            }
            guard shows else { return nil }
            return MessageActionItem(action: action, section: section(of: action), isEnabled: state == .available)
        }
    }

    // MARK: - Rules

    enum Availability: Equatable {
        case available
        case unavailable
        case notApplicable
    }

    /// The rule for one action on one message. Each B-story adds its case here.
    static func availability(of action: MessageAction, for subject: MessageActionSubject) -> Availability {
        let isRedacted = subject.content == .redacted
        let hasEventId = subject.eventId != nil

        switch action {
        case .reply, .replyInThread:
            if isRedacted { return .notApplicable }
            return subject.canBeRepliedTo ? .available : .unavailable
        case .toggleReaction, .openReactionPicker:
            // A local echo takes reactions too: the SDK keys the toggle on
            // the event or transaction ID, as the hover row always did.
            return isRedacted ? .notApplicable : .available
        case .copyText:
            guard let text = subject.copyableText, !text.isEmpty else { return .notApplicable }
            return .available
        case .copyLink:
            return hasEventId ? .available : .unavailable
        case .pin:
            if isRedacted || subject.isPinned { return .notApplicable }
            return hasEventId ? .available : .unavailable
        case .unpin:
            if isRedacted || !subject.isPinned { return .notApplicable }
            return hasEventId ? .available : .unavailable
        case .quickLook:
            switch subject.content {
            case .image, .audio, .file, .video(isPlayingInline: true):
                return .available
            case .video(isPlayingInline: false), .text, .redacted, .other:
                return .notApplicable
            }
        case .playInline:
            return subject.content == .video(isPlayingInline: false) ? .available : .notApplicable
        case .saveToDownloads:
            return subject.content.isMedia ? .available : .notApplicable
        }
    }

    /// The display order of the actions each surface can show.
    ///
    /// The Edit menu shows one Pin or Unpin item: Unpin when the target is
    /// pinned, else Pin. The menus put "Add Reaction…" after the React
    /// submenu (MATRIX-111).
    static func order(
        on surface: MessageActionSurface,
        for subject: MessageActionSubject?,
        quickReactionKeys keys: [String]
    ) -> [MessageAction] {
        let reactions: [MessageAction] = keys.map { MessageAction.toggleReaction(key: $0) }
        switch surface {
        case .contextMenu:
            return [.reply] + reactions + [.openReactionPicker]
                + [.quickLook, .playInline, .saveToDownloads]
                + [.copyText, .copyLink]
                + [.pin, .unpin]
        case .hoverRow:
            return reactions + [.openReactionPicker, .reply, .replyInThread, .pin, .unpin]
        case .editMenu:
            let pinAction: MessageAction = subject?.isPinned == true ? .unpin : .pin
            return [.reply] + reactions + [.openReactionPicker] + [.copyText, .copyLink, pinAction]
        }
    }

    static func section(of action: MessageAction) -> MessageActionSection {
        switch action {
        case .reply, .replyInThread, .toggleReaction, .openReactionPicker:
            return .respond
        case .quickLook, .playInline, .saveToDownloads:
            return .media
        case .copyText, .copyLink:
            return .copy
        case .pin, .unpin:
            return .organize
        }
    }
}

/// One line of a menu built from action items.
public enum MessageActionMenuEntry: Hashable, Sendable {
    /// A single menu item.
    case action(MessageActionItem)
    /// The quick reactions, drawn as one React submenu.
    case reactions([MessageActionItem])
    /// A separator between two sections.
    case separator
}

/// Turns ordered action items into menu lines: quick reactions fold into one
/// submenu, and a separator goes between two sections.
public enum MessageActionMenuLayout {
    /// - Parameter items: Items in display order, from `MessageActionModel`.
    /// - Returns: The menu lines, with no leading, trailing, or double separator.
    public static func entries(for items: [MessageActionItem]) -> [MessageActionMenuEntry] {
        var entries: [MessageActionMenuEntry] = []
        var previousSection: MessageActionSection?
        var pendingReactions: [MessageActionItem] = []

        func flushReactions() {
            guard !pendingReactions.isEmpty else { return }
            entries.append(.reactions(pendingReactions))
            pendingReactions = []
        }

        for item in items {
            if let previousSection, previousSection != item.section {
                flushReactions()
                entries.append(.separator)
            }
            previousSection = item.section
            if item.action.isQuickReaction {
                pendingReactions.append(item)
            } else {
                flushReactions()
                entries.append(.action(item))
            }
        }
        flushReactions()
        return entries
    }
}

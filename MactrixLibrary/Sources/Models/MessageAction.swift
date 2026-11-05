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
/// - B2 `edit`: in (MATRIX-109). Own, editable text messages and media
///   captions. Section `.modify`.
/// - B3 `redact`: own messages, or others' with the power level. Section
///   `.destructive`.
/// - B5 `forward`: in (MATRIX-112). Sent text and media messages, own or
///   other. Section `.modify`.
/// - B6 `copyMessages`: the message selection, not one message. Section
///   `.copy`.
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
    /// Edit the message in the composer (MATRIX-109, M2-B2): the text of a
    /// text message, or the caption of a media message. Own messages only.
    case edit
    /// Send the message again to another room (MATRIX-112, M2-B5, D-4): the
    /// quick switcher picks the room, then a sheet confirms. Text and media
    /// messages with an event ID, own or other. Not in the hover row.
    case forward
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
    /// Delete (redact) the message for everyone, after a confirmation with an
    /// optional reason (MATRIX-110, M2-B3). Own messages, and other people's
    /// when the power levels allow it.
    case redact
    /// Copy the selected messages as a plain-text transcript (MATRIX-113,
    /// M2-B6). It acts on the timeline's message selection, not on the
    /// message that shows the menu, so it shows only while a selection
    /// exists.
    case copyMessages

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
        case .reply, .replyInThread, .toggleReaction, .openReactionPicker, .edit, .forward, .copyText, .copyLink, .pin, .unpin, .redact,
             .copyMessages:
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
/// The raw value is the display order. `.destructive` (B3) stays last.
public enum MessageActionSection: Int, Hashable, Sendable, Comparable {
    case respond
    /// Actions that change the message: edit (B2) and forward (B5).
    case modify
    case media
    case copy
    case organize
    /// Actions that remove the message. Always the last group, so a
    /// separator keeps them away from the rest (MATRIX-110).
    case destructive

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

        /// Whether Quick Look shows the content now. A video that plays in
        /// the row offers Quick Look instead of Play Inline (S-38).
        public var opensInQuickLook: Bool {
            switch self {
            case .image, .audio, .file, .video(isPlayingInline: true):
                return true
            case .video(isPlayingInline: false), .text, .redacted, .other:
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
    /// What the signed-in account may redact in this message's room, from the
    /// room's power levels (MATRIX-110). The rule reads `isOwn` to pick one.
    public var redactPermission: MessageRedactPermission
    /// Whether the composer can edit this message (MATRIX-109): the SDK's
    /// `isEditable`, and content the composer can edit (text, or a media
    /// caption). The rule reads `isOwn` too.
    public var isEditable: Bool
    /// Whether the message's content can forward (MATRIX-112): text or a
    /// notice with a body, or one media file. `Core` sets it from
    /// `MessageForwardContent.decide(type:body:media:)`.
    public var isForwardable: Bool

    /// - Parameters:
    ///   - redactPermission: The room's redact permission. It defaults to
    ///     `.none`, so a caller that does not know the power levels never
    ///     offers Delete.
    ///   - isEditable: Whether the composer can edit the message. It
    ///     defaults to false, so a caller that does not know never offers Edit.
    ///   - isForwardable: Whether the content can forward. It defaults to
    ///     false, so a caller that does not know never offers Forward.
    public init(
        content: Content,
        isOwn: Bool,
        eventId: String?,
        canBeRepliedTo: Bool,
        isPinned: Bool,
        copyableText: String?,
        redactPermission: MessageRedactPermission = .none,
        isEditable: Bool = false,
        isForwardable: Bool = false
    ) {
        self.content = content
        self.isOwn = isOwn
        self.eventId = eventId
        self.canBeRepliedTo = canBeRepliedTo
        self.isPinned = isPinned
        self.copyableText = copyableText
        self.redactPermission = redactPermission
        self.isEditable = isEditable
        self.isForwardable = isForwardable
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
    ///   - hasMessageSelection: Whether the timeline has a message selection
    ///     (MATRIX-113). Copy Messages shows only then.
    /// - Returns: The actions in display order, each with its enabled state.
    public static func items(
        for subject: MessageActionSubject?,
        on surface: MessageActionSurface,
        quickReactionKeys keys: [String] = defaultQuickReactionKeys,
        hasMessageSelection: Bool = false
    ) -> [MessageActionItem] {
        order(on: surface, for: subject, quickReactionKeys: keys, hasMessageSelection: hasMessageSelection).compactMap { action in
            // Copy Messages reads the selection, not the message, so it is
            // available even when the Edit menu has no single target.
            let state: Availability = if action == .copyMessages {
                hasMessageSelection ? .available : .notApplicable
            } else {
                subject.map { Self.availability(of: action, for: $0) } ?? .unavailable
            }
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
        case .edit:
            // The SDK edits a local echo through its transaction ID, so an
            // own echo stays eligible when the SDK marks it editable.
            if isRedacted { return .notApplicable }
            return subject.isOwn && subject.isEditable ? .available : .notApplicable
        case .forward:
            // A local echo has no event yet: it shows disabled until the
            // send completes, as Copy Link does.
            if isRedacted || !subject.isForwardable { return .notApplicable }
            return hasEventId ? .available : .unavailable
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
            return subject.content.opensInQuickLook ? .available : .notApplicable
        case .playInline:
            return subject.content == .video(isPlayingInline: false) ? .available : .notApplicable
        case .saveToDownloads:
            return subject.content.isMedia ? .available : .notApplicable
        case .redact:
            // A local echo has no event ID, but the SDK takes the transaction
            // ID too and aborts the pending send, so an own echo stays
            // eligible. A message the power levels protect gets no item.
            if isRedacted { return .notApplicable }
            return subject.redactPermission.allows(isOwn: subject.isOwn) ? .available : .notApplicable
        case .copyMessages:
            // Decided in `items(for:on:quickReactionKeys:hasMessageSelection:)`
            // from the selection. No message fact makes it apply.
            return .notApplicable
        }
    }

    /// The display order of the actions each surface can show.
    ///
    /// The Edit menu shows one Pin or Unpin item: Unpin when the target is
    /// pinned, else Pin. Delete is not in the hover row: one stray click there
    /// must not start a destructive action. Forward is not in the hover row either
    /// (MATRIX-112): the menus carry it, after Edit. The menus put "Add Reaction…"
    /// after the React submenu (MATRIX-111). Copy Messages heads the copy
    /// group (MATRIX-113). The Edit menu lists it only while a selection
    /// exists; the context menu leaves it out through its availability.
    static func order(
        on surface: MessageActionSurface,
        for subject: MessageActionSubject?,
        quickReactionKeys keys: [String],
        hasMessageSelection: Bool = false
    ) -> [MessageAction] {
        let reactions: [MessageAction] = keys.map { MessageAction.toggleReaction(key: $0) }
        switch surface {
        case .contextMenu:
            return [.reply] + reactions + [.openReactionPicker]
                + [.edit, .forward]
                + [.quickLook, .playInline, .saveToDownloads]
                + [.copyMessages, .copyText, .copyLink]
                + [.pin, .unpin]
                + [.redact]
        case .hoverRow:
            return reactions + [.openReactionPicker, .reply, .replyInThread, .edit, .pin, .unpin]
        case .editMenu:
            let pinAction: MessageAction = subject?.isPinned == true ? .unpin : .pin
            let copySelection: [MessageAction] = hasMessageSelection ? [.copyMessages] : []
            return [.reply] + reactions + [.openReactionPicker] + [.edit, .forward]
                + copySelection + [.copyText, .copyLink, pinAction, .redact]
        }
    }

    static func section(of action: MessageAction) -> MessageActionSection {
        switch action {
        case .reply, .replyInThread, .toggleReaction, .openReactionPicker:
            return .respond
        case .edit, .forward:
            return .modify
        case .quickLook, .playInline, .saveToDownloads:
            return .media
        case .copyText, .copyLink, .copyMessages:
            return .copy
        case .pin, .unpin:
            return .organize
        case .redact:
            return .destructive
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

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
/// - `showEditHistory`: in (MATRIX-209). Edited messages with an event ID.
///   Section `.modify`, right-click menu only.
public enum MessageAction: Hashable, Sendable {
    /// Reply to the message in the composer.
    case reply
    /// Reply in the message's thread: the thread panel opens on the thread
    /// root, and its composer takes the focus (MATRIX-216). In most rooms
    /// only the hover row offers it. In a room whose network puts every
    /// reply in a thread (MATRIX-232, `ThreadedReplyRule`), it takes the
    /// place of Reply on every surface.
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
    /// Show the versions of an edited message in a popover on its row
    /// (MATRIX-209). The SDK reads the versions. Right-click menu only: the
    /// Edit menu keeps one shape, and this item would show disabled for
    /// almost every message there. A click on the "(edited)" mark runs it
    /// too.
    case showEditHistory
    /// Copy the message's plain text body or media caption.
    case copyText
    /// Copy the message's matrix.to permalink.
    case copyLink
    /// Open the original target of the message's first music link, which
    /// the body sends to song.link (MATRIX-178).
    case openOriginalLink
    /// Copy that original target.
    case copyOriginalLink
    /// Pin the message in the room.
    case pin
    /// Unpin the message.
    case unpin
    /// Bookmark the message (MATRIX-208): the account's Bookmarks list
    /// (Go > Bookmarks) shows it. Menus only, not the hover row.
    case bookmark
    /// Remove the message's bookmark (MATRIX-208).
    case removeBookmark
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

    /// Whether the action needs a view that only a room has: the thread
    /// view, or the pin list. A merged chat shows neither (MATRIX-149).
    public var needsRoomView: Bool {
        switch self {
        case .replyInThread, .pin, .unpin:
            return true
        case .reply, .toggleReaction, .openReactionPicker, .edit, .forward, .copyText, .copyLink, .quickLook, .playInline,
             .saveToDownloads, .redact, .copyMessages, .openOriginalLink, .copyOriginalLink, .bookmark, .removeBookmark,
             .showEditHistory:
            return false
        }
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
             .copyMessages, .openOriginalLink, .copyOriginalLink, .bookmark, .removeBookmark, .showEditHistory:
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
    /// Actions that change the message, or show how it changed: edit (B2),
    /// forward (B5), and edit history (MATRIX-209).
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
    /// First, for every surface (MATRIX-149): an action that needs the room's
    /// thread view or pin list does not apply in a merged chat.
    ///
    /// MATRIX-232: a merged chat keeps Reply in Thread for a message of a
    /// room that puts every reply in a thread. The merged chat has no thread
    /// panel, so the merged composer replies, and `ReplyRoute` sends the
    /// reply into the thread.
    static func availability(of action: MessageAction, for subject: MessageActionSubject) -> Availability {
        if subject.isInMergedChat, action.needsRoomView, !(action == .replyInThread && subject.repliesInThreads) {
            return .notApplicable
        }
        if action == .openOriginalLink || action == .copyOriginalLink {
            // Only a text body with a marked music link has one; a redacted
            // message has no body.
            return subject.originalMusicLink == nil ? .notApplicable : .available
        }
        if action == .bookmark || action == .removeBookmark {
            return bookmarkAvailability(of: action, for: subject)
        }
        if action == .showEditHistory {
            return editHistoryAvailability(for: subject)
        }
        return messageAvailability(of: action, for: subject)
    }

    /// Show Edit History (MATRIX-209): an edited message. The SDK reads the
    /// versions by event ID, so a local echo shows it disabled.
    private static func editHistoryAvailability(for subject: MessageActionSubject) -> Availability {
        if subject.content == .redacted || !subject.isEdited { return .notApplicable }
        return subject.eventId != nil ? .available : .unavailable
    }

    /// Bookmark and Remove Bookmark (MATRIX-208). A bookmark names the
    /// event, so a local echo shows Bookmark disabled until the send
    /// completes, as Pin does. Remove Bookmark also shows on a message
    /// deleted after it was saved.
    private static func bookmarkAvailability(of action: MessageAction, for subject: MessageActionSubject) -> Availability {
        if action == .removeBookmark {
            return subject.isBookmarked ? .available : .notApplicable
        }
        if subject.content == .redacted || subject.isBookmarked { return .notApplicable }
        return subject.eventId != nil ? .available : .unavailable
    }

    /// The rule for one action from the facts of the message alone.
    private static func messageAvailability(of action: MessageAction, for subject: MessageActionSubject) -> Availability {
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
        case .copyMessages, .openOriginalLink, .copyOriginalLink, .bookmark, .removeBookmark, .showEditHistory:
            // Copy Messages: decided in
            // `items(for:on:quickReactionKeys:hasMessageSelection:)` from the
            // selection. No message fact makes it apply. The music link,
            // bookmark, and edit history actions: decided in
            // `availability(of:for:)`.
            return .notApplicable
        }
    }

    /// The display order of the actions each surface can show.
    ///
    /// The Edit menu shows one Pin or Unpin item: Unpin when the target is
    /// pinned, else Pin. The same for Bookmark and Remove Bookmark
    /// (MATRIX-208), which are not in the hover row. Delete is not in the hover row: one stray click there
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
        let replies = replyActions(on: surface, for: subject)
        switch surface {
        case .contextMenu:
            return replies + reactions + [.openReactionPicker]
                + [.edit, .forward, .showEditHistory]
                + [.quickLook, .playInline, .saveToDownloads]
                + [.copyMessages, .copyText, .copyLink, .openOriginalLink, .copyOriginalLink]
                + [.pin, .unpin, .bookmark, .removeBookmark]
                + [.redact]
        case .hoverRow:
            return reactions + [.openReactionPicker] + replies + [.edit, .pin, .unpin]
        case .editMenu:
            let pinAction: MessageAction = subject?.isPinned == true ? .unpin : .pin
            let bookmarkAction: MessageAction = subject?.isBookmarked == true ? .removeBookmark : .bookmark
            let copySelection: [MessageAction] = hasMessageSelection ? [.copyMessages] : []
            return replies + reactions + [.openReactionPicker] + [.edit, .forward]
                + copySelection + [.copyText, .copyLink, pinAction, bookmarkAction, .redact]
        }
    }

    /// The reply actions of `surface` (MATRIX-232).
    ///
    /// In a room whose network puts every reply in a thread, Reply in Thread
    /// takes the place of Reply: no surface offers an inline reply there,
    /// and no surface shows a reply item twice. Elsewhere the menus offer
    /// Reply, and the hover row offers Reply and Reply in Thread.
    static func replyActions(on surface: MessageActionSurface, for subject: MessageActionSubject?) -> [MessageAction] {
        if subject?.repliesInThreads == true { return [.replyInThread] }
        switch surface {
        case .contextMenu, .editMenu:
            return [.reply]
        case .hoverRow:
            return [.reply, .replyInThread]
        }
    }

    static func section(of action: MessageAction) -> MessageActionSection {
        switch action {
        case .reply, .replyInThread, .toggleReaction, .openReactionPicker:
            return .respond
        case .edit, .forward, .showEditHistory:
            return .modify
        case .quickLook, .playInline, .saveToDownloads:
            return .media
        case .copyText, .copyLink, .copyMessages, .openOriginalLink, .copyOriginalLink:
            return .copy
        case .pin, .unpin, .bookmark, .removeBookmark:
            return .organize
        case .redact:
            return .destructive
        }
    }
}

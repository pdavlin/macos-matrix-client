import Foundation

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
    /// Whether the message shows in a merged chat (MATRIX-149), which has no
    /// thread view and no pin list. False is a room's own timeline.
    public var isInMergedChat: Bool
    /// The original target of the body's first music link, when the music
    /// link marker is on (MATRIX-178), as the sender wrote it. Nil when the
    /// body has no marked link.
    public var originalMusicLink: String?
    /// Whether the account's bookmarks hold this message (MATRIX-208).
    public var isBookmarked: Bool
    /// Whether the SDK reports the message as edited, which shows the
    /// "(edited)" mark (MATRIX-209).
    public var isEdited: Bool
    /// Whether every reply in the message's room belongs in a thread
    /// (MATRIX-232, `ThreadedReplyRule`): Reply in Thread then takes the
    /// place of Reply on every surface. In a merged chat it is the room that
    /// holds the message, not the merged chat.
    public var repliesInThreads: Bool

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
        isForwardable: Bool = false,
        isInMergedChat: Bool = false,
        originalMusicLink: String? = nil,
        isBookmarked: Bool = false,
        isEdited: Bool = false,
        repliesInThreads: Bool = false
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
        self.isInMergedChat = isInMergedChat
        self.originalMusicLink = originalMusicLink
        self.isBookmarked = isBookmarked
        self.isEdited = isEdited
        self.repliesInThreads = repliesInThreads
    }

    /// The same subject with other content. A video view uses it to report
    /// whether it plays inline.
    public func with(content: Content) -> Self {
        var copy = self
        copy.content = content
        return copy
    }
}

import Foundation

/// The message types the forward rule sorts (MATRIX-112, M2-B5, D-4).
///
/// `Core` maps each SDK `MessageType` case to one of these, so the
/// text-or-media decision is plain logic with unit tests.
public enum MessageForwardSourceType: Equatable, Sendable {
    case text
    case notice
    case emote
    case location
    case image
    case video
    case audio
    case file
    case gallery
    case other
}

/// What a forward sends again (MATRIX-112, D-4).
///
/// The pinned SDK has no forward call, and hand-built event content would
/// break hard rule 1. So a forward is a new send through the SDK:
/// - text: the original body, sent again through
///   `messageEventContentFromMarkdown` and `Timeline.send(msg:)`;
/// - media: the file, downloaded through the SDK and uploaded again through
///   `sendImage`, `sendVideo`, `sendAudio`, or `sendFile`.
public enum MessageForwardContent: Equatable, Sendable {
    /// A text message. `body` is the original body as sent.
    case text(body: String)
    /// One media file.
    case media(MessageForwardMedia)

    /// The text-or-media decision for one message.
    ///
    /// - Text and notices forward their body. Empty or blank text does not
    ///   forward.
    /// - Images, videos, audio, and files forward their file and caption.
    /// - Emotes, locations, galleries, and other types do not forward. A
    ///   new text send would change an emote or a location into plain text,
    ///   and a gallery has no single file to send again.
    ///
    /// - Parameters:
    ///   - type: The message type.
    ///   - body: The message body. Media bodies are not read.
    ///   - media: The file facts. Read for media types only; nil there means
    ///     the message does not forward.
    /// - Returns: The content to forward, or nil when the message does not
    ///   forward.
    public static func decide(
        type: MessageForwardSourceType,
        body: String,
        media: MessageForwardMedia? = nil
    ) -> MessageForwardContent? {
        switch type {
        case .text, .notice:
            let isBlank = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return isBlank ? nil : .text(body: body)
        case .image, .video, .audio, .file:
            return media.map(MessageForwardContent.media)
        case .emote, .location, .gallery, .other:
            return nil
        }
    }

    /// The message to send for a text forward: the original body as
    /// markdown, with the users it mentions.
    ///
    /// The body of a message this app sent is the markdown the composer
    /// made, so each `matrix.to` pill link stays a pill and goes into
    /// `Mentions.userIds` again (MATRIX-105). The draft-text parser keeps all
    /// other text as it is, and its boundary escapes do not change text that
    /// already has them.
    ///
    /// - Parameter body: The original body.
    /// - Returns: The markdown for `messageEventContentFromMarkdown`, and the
    ///   mentioned user IDs.
    public static func outgoingText(body: String) -> ComposerOutgoingMessage {
        MentionMarkdown.outgoingMessage(fromDraftText: body)
    }
}

/// The facts about one media file that the forward needs to show and send.
public struct MessageForwardMedia: Equatable, Sendable {
    /// Which SDK send call uploads the file again.
    public let kind: MediaSendKind
    /// The file name, for the preview and the download.
    public let filename: String
    /// The caption as sent, or nil. The forward sends it again.
    public let caption: String?
    /// The file size in bytes from the event, or nil when the event has none.
    public let byteCount: UInt64?

    public init(kind: MediaSendKind, filename: String, caption: String?, byteCount: UInt64?) {
        self.kind = kind
        self.filename = filename
        self.caption = caption
        self.byteCount = byteCount
    }

    /// The caption without leading and trailing white space, or nil when
    /// nothing is left.
    public var trimmedCaption: String? {
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Display rules for the forward confirmation (MATRIX-112).
///
/// Pure logic, so it is unit-tested in `ModelsTests`. The sheet in `UI`
/// words its title from these values.
public enum MessageForwardPreview {
    /// The longest preview text, in characters, before it is cut.
    public static let maximumPreviewLength = 280

    /// The file size as the confirmation shows it, for example "24.3 MB".
    ///
    /// - Parameters:
    ///   - byteCount: The size in bytes.
    ///   - locale: The locale for the number format. Tests set it.
    /// - Returns: The size in file-size units (powers of 1000, as Finder
    ///   shows them).
    public static func sizeText(byteCount: UInt64, locale: Locale = .current) -> String {
        let style = ByteCountFormatStyle(style: .file, locale: locale)
        return style.format(Int64(clamping: byteCount))
    }

    /// The size text of the content, or nil for text and for media with no
    /// size in its event.
    ///
    /// - Parameters:
    ///   - content: The forwarded content.
    ///   - locale: The locale for the number format.
    public static func sizeText(of content: MessageForwardContent, locale: Locale = .current) -> String? {
        guard case let .media(media) = content, let byteCount = media.byteCount else { return nil }
        return sizeText(byteCount: byteCount, locale: locale)
    }

    /// The text the confirmation shows under its title.
    ///
    /// - Text: the body with each mention pill as "@name", cut after
    ///   `maximumPreviewLength` characters.
    /// - Media: the caption, in the same form, or nil when there is no
    ///   caption. The sheet shows the file name on its own line.
    ///
    /// - Parameter content: The forwarded content.
    /// - Returns: The preview text, or nil when there is none.
    public static func text(of content: MessageForwardContent) -> String? {
        let source: String? = switch content {
        case let .text(body): body
        case let .media(media): media.trimmedCaption
        }
        guard let source else { return nil }
        let plain = MentionMarkdown.plainText(for: MentionMarkdown.segments(fromDraftText: source))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return nil }
        return truncated(plain, to: maximumPreviewLength)
    }

    /// Cuts `text` after `limit` characters and adds an ellipsis.
    static func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut + "…"
    }
}

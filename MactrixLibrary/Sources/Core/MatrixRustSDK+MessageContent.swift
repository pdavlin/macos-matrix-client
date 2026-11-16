import MatrixRustSDK
import Models

public protocol MessageContent {
    var body: String { get }
    var formatted: FormattedBody? { get }
}

public extension MessageContent {
    /// The plain body as a person reads it (MATRIX-156): each custom emoji
    /// tag that the composer put into the body is its `:name:` again
    /// (`ComposerEmojiMarkup.draftText(fromBody:)`). All other text,
    /// including other HTML a user typed, stays as it is.
    ///
    /// Use this for every place that shows or copies the plain body: a
    /// preview, a notification, a reply quote, the pasteboard. Use `body`
    /// only where the text as sent matters (a forward, a measurement key).
    var displayBody: String {
        ComposerEmojiMarkup.draftText(fromBody: body)
    }
}

public extension MatrixRustSDK.MessageContent {
    /// The plain body of a message of any type as a person reads it
    /// (MATRIX-156). The rule of `Core.MessageContent.displayBody`.
    var displayBody: String {
        ComposerEmojiMarkup.draftText(fromBody: body)
    }
}

public protocol MediaMessageContent {
    var filename: String { get }
    var caption: String? { get }
    var formattedCaption: FormattedBody? { get }
    var source: MediaSource { get }
}

extension FileMessageContent: MediaMessageContent {}
extension AudioMessageContent: MediaMessageContent {}
extension VideoMessageContent: MediaMessageContent {}
extension ImageMessageContent: MediaMessageContent {}

extension EmoteMessageContent: MessageContent {}
extension NoticeMessageContent: MessageContent {}
extension TextMessageContent: MessageContent {}

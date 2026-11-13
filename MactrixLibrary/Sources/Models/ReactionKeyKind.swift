import Foundation

/// What a reaction key draws as (MATRIX-154).
///
/// A reaction key is free text. Most keys are one emoji. The Slack bridge
/// sends a custom emoji as an `mxc://` URI (`custom_emoji_reactions: true`)
/// or as `:name:` text (`false`). A chip, a quick reaction, and a menu title
/// all ask this type what to draw, so the rule lives in one place.
///
/// Usage:
/// ```swift
/// switch ReactionKeyKind(key: reaction.key) {
/// case let .image(mxcUrl): // load and draw the image
/// case .unicode, .shortcode: // draw the key as text
/// }
/// ```
public enum ReactionKeyKind: Equatable, Sendable {
    /// Text that draws verbatim: an emoji, or any other string.
    case unicode(String)
    /// A custom emoji image. `mxcUrl` is the key, unchanged.
    case image(mxcUrl: String)
    /// A `:name:` shortcode. The associated value is the name without the
    /// colons. The chip draws the key verbatim, colons included.
    case shortcode(String)

    private static let mxcScheme = "mxc://"

    /// Sorts `key`. The key is an image only when it is a complete media
    /// URI: the `mxc://` scheme, a server name, one `/`, and a media ID,
    /// with no whitespace. Anything else is text.
    public init(key: String) {
        if Self.isMediaUri(key) {
            self = .image(mxcUrl: key)
        } else if let name = Self.shortcodeName(of: key) {
            self = .shortcode(name)
        } else {
            self = .unicode(key)
        }
    }

    /// True when the key draws as an image.
    public var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    /// The name to speak or show where the image cannot draw: the shortcode
    /// name, the text itself, or "custom emoji" for an image, whose name the
    /// reaction event does not carry through the SDK.
    public var spokenName: String {
        switch self {
        case let .unicode(text): text
        case .image: Self.customEmojiName
        case let .shortcode(name): name
        }
    }

    /// The name of an image key with no known shortcode.
    public static let customEmojiName = "custom emoji"

    private static func isMediaUri(_ key: String) -> Bool {
        guard key.hasPrefix(mxcScheme), !key.contains(where: \.isWhitespace) else { return false }
        let parts = key.dropFirst(mxcScheme.count).split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
    }

    private static func shortcodeName(of key: String) -> String? {
        guard key.count >= 3, key.hasPrefix(":"), key.hasSuffix(":") else { return nil }
        let name = key.dropFirst().dropLast()
        guard !name.contains(where: { $0 == ":" || $0.isWhitespace }) else { return nil }
        return String(name)
    }
}

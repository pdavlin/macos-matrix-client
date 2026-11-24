import Foundation

/// One replacement in the composer text: `text` goes in place of `range`.
///
/// The composer puts an edit into its text view as plain text, through the
/// view's `insertText`, so undo and the draft see a typed edit. The emoji
/// completion pick (MATRIX-156) and the emoji picker pick (MATRIX-234) both
/// make an edit, and the composer applies both in the same way.
public struct ComposerTextEdit: Equatable, Sendable {
    /// The UTF-16 range that the edit replaces.
    public let range: NSRange
    /// The text that goes in.
    public let text: String

    public init(range: NSRange, text: String) {
        self.range = range
        self.text = text
    }

    /// The UTF-16 caret location after the edit: after the new text.
    public var caretAfter: Int {
        range.location + (text as NSString).length
    }

    /// `text` with the edit applied, or nil if `range` is not in `text`.
    public func applied(to text: String) -> String? {
        let source = text as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= source.length else { return nil }
        return source.replacingCharacters(in: range, with: self.text)
    }
}

public extension ComposerEmojiCompletion {
    /// The edit of a completion pick: the emoji's token and a space in place
    /// of the open ":" query.
    static func edit(for emoji: ImagePackEmoji, replacing trigger: ComposerEmojiTrigger) -> ComposerTextEdit {
        ComposerTextEdit(range: trigger.range, text: insertion(for: emoji))
    }
}

/// One pick of the composer's emoji picker (MATRIX-234).
///
/// The composer's emoji button opens the app's picker (`UI.ReactionPickerView`).
/// A pick goes into the composer text in place of the selection:
/// - A Unicode emoji goes in as text, with nothing around it.
/// - A custom emoji goes in as its `:name:` token and a space: the same text
///   as a pick of the ":" completion list (`ComposerEmojiCompletion.insertion(for:)`).
///   The draft stays plain text, and the send makes the emoticon tag
///   (`ComposerEmojiMarkup`), as for a completion pick. A space goes before
///   the token when the text before the selection ends in a letter or a
///   digit, because the send keeps a token there as text.
///
/// Usage:
/// ```swift
/// let edit = ComposerEmojiPick(entry: entry).edit(in: text, selection: selection)
/// ```
public enum ComposerEmojiPick: Equatable, Sendable {
    /// A Unicode emoji, for example "👍".
    case unicode(String)
    /// A custom emoji of the room's image packs.
    case custom(ImagePackEmoji)

    /// The pick of one picker cell. A custom emoji's cell holds the image URL
    /// as its value and the shortcode as its name (`ImagePackSection`). Two
    /// shortcodes can share one image, so the pick keeps the cell's name.
    public init(entry: EmojiCatalog.Entry) {
        if entry.isImage {
            self = .custom(ImagePackEmoji(shortcode: entry.name, url: entry.value))
        } else {
            self = .unicode(entry.value)
        }
    }

    /// The key that a reaction with this emoji sends: the emoji, or the image
    /// URL. The composer records it as a use in the account's recent list,
    /// as a reaction pick does. The list does not record an image key.
    public var key: String {
        switch self {
        case let .unicode(emoji): emoji
        case let .custom(emoji): emoji.url
        }
    }

    /// The edit that puts the pick into the composer text.
    ///
    /// - Parameters:
    ///   - text: the composer text, as `NSTextView.string` gives it.
    ///   - selection: the UTF-16 selection. An empty selection is the caret.
    /// - Returns: the edit that replaces the selection.
    public func edit(in text: String, selection: NSRange) -> ComposerTextEdit {
        switch self {
        case let .unicode(emoji):
            return ComposerTextEdit(range: selection, text: emoji)
        case let .custom(emoji):
            let token = ComposerEmojiCompletion.insertion(for: emoji)
            let space = Self.needsSpace(before: selection.location, in: text) ? " " : ""
            return ComposerTextEdit(range: selection, text: space + token)
        }
    }

    /// Whether the character before `location` keeps a token as text.
    static func needsSpace(before location: Int, in text: String) -> Bool {
        let source = text as NSString
        guard location > 0, location <= source.length,
              let previous = source.substring(to: location).last
        else { return false }
        return !ComposerEmojiMarkup.tokenCanFollow(previous)
    }
}

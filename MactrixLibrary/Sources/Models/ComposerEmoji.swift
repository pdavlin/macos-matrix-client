import Foundation

/// A ":" query that is open in the composer (MATRIX-156): the ":" and the
/// name the user typed after it, up to the caret.
///
/// The completion list offers the custom emoji of the chat's image packs for
/// this query. A pick replaces `range` with the text ":name: ". The draft
/// stays plain text; `ComposerEmojiMarkup` makes the emoticon at send time.
public struct ComposerEmojiTrigger: Equatable, Sendable {
    /// The UTF-16 range from the ":" to the caret.
    public let range: NSRange
    /// The text after the ":".
    public let query: String

    /// The shortest query that opens the list.
    public static let minimumQueryLength = 2

    /// The longest query that keeps the list open.
    public static let maximumQueryLength = 64

    public init(range: NSRange, query: String) {
        self.range = range
        self.query = query
    }

    /// Finds the open ":" query that ends at the caret.
    ///
    /// The ":" must start the text or follow whitespace, a chip, or an
    /// opening bracket or quote (the rule of `MentionTrigger`), so the ":" in
    /// "10:30" or in a URL does not open the list. The query has two or more
    /// characters, each a letter, a digit, or one of `_ - + '`.
    ///
    /// - Parameters:
    ///   - text: the composer text, as `NSTextView.string` gives it.
    ///   - caret: the UTF-16 caret offset, or nil for a selection that is not
    ///     empty.
    /// - Returns: the trigger, or nil if no ":" query is open.
    public static func find(in text: String, caret: Int?) -> ComposerEmojiTrigger? {
        guard let caret else { return nil }
        let utf16 = text as NSString
        guard caret >= 1, caret <= utf16.length else { return nil }

        var index = caret - 1
        while index >= 0, caret - index - 1 <= maximumQueryLength {
            let unit = utf16.character(at: index)
            if unit == UInt16(UInt8(ascii: ":")) {
                let queryLength = caret - index - 1
                guard queryLength >= minimumQueryLength else { return nil }
                guard index == 0 || MentionTrigger.opensQuery(utf16.character(at: index - 1)) else { return nil }
                return ComposerEmojiTrigger(
                    range: NSRange(location: index, length: caret - index),
                    query: utf16.substring(with: NSRange(location: index + 1, length: queryLength))
                )
            }
            guard isQueryUnit(unit) else { return nil }
            index -= 1
        }
        return nil
    }

    /// Whether a UTF-16 unit can be part of a query.
    static func isQueryUnit(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || "_-+'".unicodeScalars.contains(scalar)
    }
}

/// The rows of the composer's emoji completion list (MATRIX-156).
public enum ComposerEmojiCompletion {
    /// The most rows the list shows.
    public static let defaultLimit = 8

    /// The custom emoji to show for a query, by the search rule of
    /// `ImagePack.search(_:)`: the shortcodes that start with the query
    /// first, then the shortcodes that contain it. A shortcode that two
    /// packs have shows one time, with the image of the first pack, which is
    /// the image that `ComposerEmojiMarkup` sends.
    ///
    /// - Parameters:
    ///   - query: the text after ":".
    ///   - packs: the image packs of the chat's room. Empty gives no row.
    ///   - limit: the most results to return.
    public static func suggestions(
        for query: String,
        in packs: [ImagePack],
        limit: Int = defaultLimit
    ) -> [ImagePackEmoji] {
        let needle = query.lowercased()
        var seen = Set<String>()
        var prefixMatches: [ImagePackEmoji] = []
        var otherMatches: [ImagePackEmoji] = []
        for pack in packs {
            for emoji in pack.search(query) where seen.insert(emoji.shortcode).inserted {
                if emoji.shortcode.lowercased().hasPrefix(needle) {
                    prefixMatches.append(emoji)
                } else {
                    otherMatches.append(emoji)
                }
            }
        }
        return Array((prefixMatches + otherMatches).prefix(max(0, limit)))
    }

    /// The text a pick puts into the composer: the token and a space.
    public static func insertion(for emoji: ImagePackEmoji) -> String {
        ":" + emoji.shortcode + ": "
    }
}

/// The open emoji completion list: the query, the rows, and the selected row.
public typealias EmojiAutocompleteState = ComposerAutocompleteState<ComposerEmojiTrigger, ImagePackEmoji>

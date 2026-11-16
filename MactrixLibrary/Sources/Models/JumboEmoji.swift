import Foundation

/// The rule that picks which text messages render their emoji large
/// (MATRIX-137).
///
/// A body is jumbo when, ignoring whitespace, it holds only emoji, and from
/// one to `maximumCount` of them. Beeper and Slack draw such messages large;
/// this is the same idea, as a pure function so the view only draws the
/// answer and the tests pin the rule.
///
/// Emoji are counted by grapheme cluster (Swift `Character`), so a family
/// joined by ZWJ, a flag, a keycap, and a thumb with a skin tone each count
/// as one, which is how a reader counts them.
///
/// A custom emoticon counts as one emoji (MATRIX-162). It exists only in the
/// HTML body, as an `<img>` that `EmoticonImageTag` accepts, so a message with
/// an HTML body is judged on that body: see `kind(body:formattedBody:)`.
///
/// Only the body decides. A reply qualifies like any other message, because
/// the reply preview is drawn from the replied-to event, not from this body.
/// An edited message is judged on the content the SDK reports, which is the
/// latest edit.
public enum JumboEmoji {
    /// The most emoji a jumbo body may hold. Ten or more draw at body size.
    public static let maximumCount = 9

    /// ZERO WIDTH JOINER, which glues emoji into one sequence.
    private static let zeroWidthJoiner: Unicode.Scalar = "\u{200D}"
    /// VARIATION SELECTOR-16, which asks for the emoji form of its base.
    private static let emojiVariationSelector: Unicode.Scalar = "\u{FE0F}"
    /// VARIATION SELECTOR-15, which asks for the text form of its base.
    private static let textVariationSelector: Unicode.Scalar = "\u{FE0E}"
    /// COMBINING ENCLOSING KEYCAP, the end of a keycap sequence such as 1️⃣.
    private static let combiningEnclosingKeycap: Unicode.Scalar = "\u{20E3}"
    /// REGIONAL INDICATOR SYMBOL LETTER A to Z. Two of them make a flag.
    private static let regionalIndicators: ClosedRange<UInt32> = 0x1F1E6 ... 0x1F1FF

    /// How a jumbo body draws.
    public enum Kind: Equatable, Sendable {
        /// Unicode emoji only, and no markup: the plain body draws large
        /// (`jumboText(body:formattedBody:)` gives the text).
        case text
        /// An HTML body of only emoji, custom emoticons among them or with
        /// markup that carries no text: the HTML body draws at the jumbo size.
        case formatted
    }

    /// The tags a jumbo HTML body may hold besides the emoticon `<img>`. None
    /// of them draws text. Each must have no attribute.
    private static let textlessTags = ["p", "/p", "br", "span", "/span", "/img"]

    /// Whether a text message draws jumbo, and how. Nil means body size.
    ///
    /// - With no HTML body, the plain body decides (`isEmojiOnly`).
    /// - With an HTML body equal to the plain body, the same, as before
    ///   MATRIX-162.
    /// - With any other HTML body, that body decides
    ///   (`isEmojiOnly(formattedBody:)`). The plain body does not: for a
    ///   bridged custom emoji it holds `:name:`, which is text.
    ///
    /// The answer comes from the two bodies alone, before any image loads.
    /// `MessageBodyGeometry` asks once for each mapped item and stores it.
    ///
    /// ```swift
    /// JumboEmoji.kind(body: "👍", formattedBody: nil) // .text
    /// JumboEmoji.kind(body: ":parrot:", formattedBody: #"<img data-mx-emoticon src="mxc://a/b" alt=":parrot:">"#) // .formatted
    /// JumboEmoji.kind(body: ":parrot:", formattedBody: nil) // nil
    /// ```
    public static func kind(body: String, formattedBody: String?) -> Kind? {
        if jumboText(body: body, formattedBody: formattedBody) != nil {
            return .text
        }
        if let formattedBody, isEmojiOnly(formattedBody: formattedBody) {
            return .formatted
        }
        return nil
    }

    /// Whether an HTML body holds only emoji and whitespace, with 1 to
    /// `maximumCount` emoji, where an emoji is a Unicode emoji or a custom
    /// emoticon `<img>`.
    ///
    /// The body qualifies when every piece of it is one of these:
    /// - an `<img>` that `EmoticonImageTag` accepts as a custom emoticon,
    /// - a Unicode emoji (`isEmoji`),
    /// - whitespace,
    /// - `<p>`, `</p>`, `<br>`, `<span>`, `</span>`, or `</img>`, with no
    ///   attribute (`<br/>` is fine).
    ///
    /// Anything else means false: other text, a character entity, any other
    /// tag, an `<img>` that is not a custom emoticon, a `<span>` with an
    /// attribute (it can be a spoiler), a `<` with no `>`.
    ///
    /// One pass, and it stops at the first piece that does not qualify, so a
    /// prose message costs a tag or two and one character. Only an `<img>`
    /// runs the tag reader's regular expressions, at most `maximumCount + 1`
    /// times.
    public static func isEmojiOnly(formattedBody html: String) -> Bool {
        var emojiCount = 0
        var index = html.startIndex
        while index < html.endIndex {
            let character = html[index]
            if character == "<" {
                guard let end = html[index...].firstIndex(of: ">") else { return false }
                let tag = html[index ... end]
                index = html.index(after: end)
                if isTextlessTag(tag) {
                    continue
                }
                guard isEmoticonTag(tag) else { return false }
            } else {
                index = html.index(after: index)
                if character.isWhitespace {
                    continue
                }
                guard isEmoji(character) else { return false }
            }
            emojiCount += 1
            if emojiCount > maximumCount {
                return false
            }
        }
        return emojiCount > 0
    }

    /// Whether `tag`, from `<` to `>`, is one of `textlessTags`. Compared as
    /// UTF-8 bytes, because this runs for the first tag of every HTML body.
    private static func isTextlessTag(_ tag: Substring) -> Bool {
        var name = tag.utf8.dropFirst().dropLast()
        // `<br/>`, `<br />`, `<p >`.
        while let last = name.last, last == UInt8(ascii: "/") || isASCIIWhitespace(last), name.count > 1 {
            name = name.dropLast()
        }
        return textlessTags.contains { $0.utf8.elementsEqual(name.lazy.map(asciiLowercased)) }
    }

    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (0x09 ... 0x0D).contains(byte)
    }

    private static func asciiLowercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(byte) ? byte | 0x20 : byte
    }

    /// Whether `tag`, from `<` to `>`, is a custom emoticon `<img>`.
    ///
    /// A tag that holds one of the body renderer's two marker characters
    /// (U+FFF9, U+FFFB) does not count: the renderer removes them before it
    /// reads the tag, so it could read another name than this does.
    private static func isEmoticonTag(_ tag: Substring) -> Bool {
        guard "img".utf8.elementsEqual(tag.utf8.dropFirst().prefix(3).lazy.map(asciiLowercased)) else { return false }
        guard !tag.unicodeScalars.contains(where: { $0 == "\u{FFF9}" || $0 == "\u{FFFB}" }) else { return false }
        return EmoticonImageTag.isEmoticon(tag: String(tag))
    }

    /// The text a jumbo body draws, or nil when the body is not jumbo text.
    ///
    /// The returned text is the body without leading or trailing whitespace,
    /// so a stray trailing newline cannot add an empty 40 pt line.
    ///
    /// - Parameters:
    ///   - body: the plain-text body of a text message.
    ///   - formattedBody: the HTML body, when the message has one. A message
    ///     with an HTML body qualifies only when that body is the same text as
    ///     the plain body (after trimming). Any markup, link, or custom emoji
    ///     image makes it differ, and it then renders as formatted text, which
    ///     `kind(body:formattedBody:)` can still find to be jumbo.
    /// - Returns: the trimmed body when it is jumbo text, else nil.
    ///
    /// ```swift
    /// JumboEmoji.jumboText(body: " 👍🏽 ", formattedBody: nil) // "👍🏽"
    /// JumboEmoji.jumboText(body: "ok 👍", formattedBody: nil) // nil
    /// ```
    public static func jumboText(body: String, formattedBody: String?) -> String? {
        guard isEmojiOnly(body) else { return nil }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let formattedBody, formattedBody.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedBody {
            return nil
        }
        return trimmedBody
    }

    /// Whether `text` holds only emoji and whitespace, with 1 to
    /// `maximumCount` emoji.
    ///
    /// One pass, and it stops at the first character that is neither emoji
    /// nor whitespace, or at the first emoji past the limit. A long prose
    /// message therefore costs one character check, which matters because
    /// the timeline asks this for every text row it draws or measures.
    public static func isEmojiOnly(_ text: String) -> Bool {
        var emojiCount = 0
        for character in text {
            if character.isWhitespace {
                continue
            }
            guard isEmoji(character) else { return false }
            emojiCount += 1
            if emojiCount > maximumCount {
                return false
            }
        }
        return emojiCount > 0
    }

    /// Whether one grapheme cluster draws as an emoji.
    ///
    /// A character is an emoji when any of these is true:
    /// - it is a ZWJ sequence of emoji (👨‍👩‍👧),
    /// - it has a scalar with default emoji presentation (👍, 🎉),
    /// - its base is a non-ASCII emoji scalar followed by VS16 (❤️, ©️),
    /// - it is a flag, two regional indicators (🇺🇸),
    /// - it is a keycap sequence (1️⃣, #️⃣),
    /// - it has a skin-tone modifier (👍🏽).
    ///
    /// It is never an emoji when it holds VS15, the explicit request for the
    /// text form. Characters that are emoji only by Unicode's broad `Emoji`
    /// property but draw as text by default are not emoji here: plain digits,
    /// "#", "*", and "©", "®", "❤" without VS16. A sender who typed "❤"
    /// without VS16 sees a text glyph in most clients, so it stays body size.
    public static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let base = scalars.first else { return false }
        if scalars.contains(textVariationSelector) {
            return false
        }
        if scalars.contains(combiningEnclosingKeycap) {
            return true
        }
        // An ASCII base ("1", "#", "*") with VS16 but no keycap is not a
        // defined emoji sequence, and draws as a plain digit or sign.
        if scalars.contains(emojiVariationSelector), base.properties.isEmoji, !base.isASCII {
            return true
        }
        // A ZWJ sequence joins two or more emoji. A lone ZWJ after a letter
        // or digit stays in that character's cluster and is not one.
        if scalars.contains(zeroWidthJoiner), scalars.count(where: { $0.properties.isEmoji }) >= 2 {
            return true
        }
        if scalars.count == 2, scalars.allSatisfy({ regionalIndicators.contains($0.value) }) {
            return true
        }
        return scalars.contains { $0.properties.isEmojiPresentation || $0.properties.isEmojiModifier }
    }
}

public extension MessageBodyGeometry {
    /// Whether this body draws as jumbo emoji (MATRIX-137, MATRIX-162).
    ///
    /// A jumbo body is taller than the same text at body size, so the flip is
    /// a height change. `jumboEmoji` is derived from `variant`, `text`, and
    /// `formattedText` alone, so a body cannot flip between jumbo and not
    /// while those three stay equal. An edit from "👍" to "ok 👍" changes
    /// `text`, and the row is measured again.
    var isJumboEmoji: Bool {
        jumboEmoji != nil
    }
}

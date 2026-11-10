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

    /// The text a jumbo body draws, or nil when the body is not jumbo.
    ///
    /// The returned text is the body without leading or trailing whitespace,
    /// so a stray trailing newline cannot add an empty 40 pt line.
    ///
    /// - Parameters:
    ///   - body: the plain-text body of a text message.
    ///   - formattedBody: the HTML body, when the message has one. A message
    ///     with an HTML body qualifies only when that body is the same text as
    ///     the plain body (after trimming). Any markup, link, or custom emoji
    ///     image makes it differ, and it then renders as formatted text.
    /// - Returns: the trimmed body when it is jumbo, else nil.
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
    /// Whether this body draws as jumbo emoji (MATRIX-137).
    ///
    /// A jumbo body is taller than the same text at body size, so the flip is
    /// a height change. It needs no field of its own in the fingerprint: the
    /// rule reads only `variant`, `text`, and `formattedText`, and those are
    /// already compared, so a body cannot flip between jumbo and not while its
    /// fingerprint stays equal. An edit from "👍" to "ok 👍" changes `text`,
    /// and the row is measured again.
    var isJumboEmoji: Bool {
        variant == "text" && JumboEmoji.jumboText(body: text, formattedBody: formattedText) != nil
    }
}

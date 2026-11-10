import Foundation
@testable import Models
import Testing

/// MATRIX-137: which text bodies draw as jumbo emoji.
///
/// Escapes spell out the sequences whose scalars matter, so a test reads the
/// same in any editor and an editor cannot drop a VS16 or a ZWJ unnoticed.
struct JumboEmojiTests {
    private func isJumbo(_ body: String, formatted: String? = nil) -> Bool {
        JumboEmoji.jumboText(body: body, formattedBody: formatted) != nil
    }

    // MARK: - One emoji of each shape

    @Test(arguments: [
        "\u{1F44D}", // 👍 default emoji presentation
        "\u{1F44D}\u{1F3FD}", // 👍🏽 skin-tone modifier
        "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", // 👨‍👩‍👧 ZWJ family
        "\u{1F1FA}\u{1F1F8}", // 🇺🇸 flag
        "1\u{FE0F}\u{20E3}", // 1️⃣ keycap
        "#\u{FE0F}\u{20E3}", // #️⃣ keycap
        "\u{2764}\u{FE0F}", // ❤️ text-default base with VS16
        "\u{00A9}\u{FE0F}", // ©️ with VS16
        "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}", // 🏳️‍🌈 ZWJ with VS16
        "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}", // England tag flag
    ])
    func singleEmojiIsJumbo(body: String) {
        #expect(isJumbo(body))
        #expect(JumboEmoji.isEmoji(Character(body)))
    }

    @Test(arguments: [
        "1",
        "#",
        "*",
        "\u{00A9}", // © without VS16
        "\u{00AE}", // ® without VS16
        "\u{2764}", // ❤ without VS16: text by default, so body size
        "\u{263A}", // ☺ without VS16
        "\u{2122}", // ™
        "1\u{FE0F}", // a digit with VS16 but no keycap
        "1\u{200D}", // a stray ZWJ after a digit
        "\u{1F44D}\u{FE0E}", // 👍 with VS15, the explicit text form
        "a",
        "\u{00E9}", // é
        "\u{3042}", // あ
    ])
    func textCharacterIsNotJumbo(body: String) {
        #expect(!isJumbo(body))
        #expect(!JumboEmoji.isEmoji(Character(body)))
    }

    // MARK: - Counting

    @Test
    func emojiSeparatedBySpacesAreJumbo() {
        #expect(isJumbo("\u{1F44D} \u{1F44D}"))
    }

    @Test
    func emojiOnSeveralLinesAreJumbo() {
        #expect(isJumbo("\u{1F44D}\n\u{1F389}"))
    }

    @Test
    func nineEmojiAreJumbo() {
        #expect(isJumbo(String(repeating: "\u{1F389}", count: 9)))
    }

    @Test
    func tenEmojiAreNotJumbo() {
        #expect(!isJumbo(String(repeating: "\u{1F389}", count: 10)))
    }

    @Test
    func countIsByGraphemeClusterNotScalar() {
        // Nine families are 45 scalars and nine characters.
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        #expect(isJumbo(String(repeating: family, count: 9)))
        #expect(!isJumbo(String(repeating: family, count: 10)))
    }

    @Test
    func whitespaceDoesNotCount() {
        #expect(isJumbo("  " + Array(repeating: "\u{1F389}", count: 9).joined(separator: " ") + "\n"))
    }

    // MARK: - Mixed and empty

    @Test(arguments: [
        "ok \u{1F44D}",
        "\u{1F44D} ok",
        "\u{1F44D}!",
        "1 \u{1F44D}",
        "\u{1F44D}\u{2764}", // one emoji next to a text-default heart
    ])
    func mixedTextIsNotJumbo(body: String) {
        #expect(!isJumbo(body))
    }

    @Test(arguments: ["", " ", "\n\t ", "\u{00A0}"])
    func emptyOrWhitespaceIsNotJumbo(body: String) {
        #expect(!isJumbo(body))
    }

    // MARK: - The drawn text

    @Test
    func jumboTextIsTrimmed() {
        #expect(JumboEmoji.jumboText(body: "\n \u{1F44D} \u{1F44D} \n", formattedBody: nil) == "\u{1F44D} \u{1F44D}")
    }

    // MARK: - Formatted bodies

    @Test
    func formattedBodyEqualToPlainBodyIsJumbo() {
        #expect(isJumbo("\u{1F44D}", formatted: "\u{1F44D}"))
        #expect(isJumbo("\u{1F44D}", formatted: " \u{1F44D}\n"))
    }

    @Test(arguments: [
        "<b>\u{1F44D}</b>",
        "<a href=\"https://example.org\">\u{1F44D}</a>",
        "<p>\u{1F44D}</p>",
        "<img data-mx-emoticon src=\"mxc://example.org/abc\" alt=\":party:\">",
    ])
    func formattedBodyWithMarkupIsNotJumbo(formatted: String) {
        #expect(!isJumbo("\u{1F44D}", formatted: formatted))
    }

    // MARK: - Body geometry

    @Test
    func geometryIsJumboOnlyForTextVariant() {
        #expect(MessageBodyGeometry(variant: "text", text: "\u{1F44D}").isJumboEmoji)
        #expect(!MessageBodyGeometry(variant: "notice", text: "\u{1F44D}").isJumboEmoji)
        #expect(!MessageBodyGeometry(variant: "emote", text: "\u{1F44D}").isJumboEmoji)
        #expect(!MessageBodyGeometry(variant: "text", text: "ok \u{1F44D}").isJumboEmoji)
        #expect(!MessageBodyGeometry(variant: "text", text: "\u{1F44D}", formattedText: "<b>\u{1F44D}</b>").isJumboEmoji)
    }
}

import Foundation
@testable import Models
import Testing

/// MATRIX-154: which reaction keys draw as an image.
struct ReactionKeyKindTests {
    @Test(arguments: [
        "mxc://example.org/abcDEF123",
        "mxc://matrix.example.org:8448/abc-def_123",
        "mxc://localhost/a",
    ])
    func mediaUriIsAnImage(key: String) {
        #expect(ReactionKeyKind(key: key) == .image(mxcUrl: key))
        #expect(ReactionKeyKind(key: key).isImage)
    }

    @Test(arguments: [
        "mxc://",
        "mxc://example.org",
        "mxc://example.org/",
        "mxc:///abc",
        "mxc://example.org/abc/def",
        "mxc://example.org/abc def",
        " mxc://example.org/abc",
        "MXC://example.org/abc",
        "https://example.org/abc",
        "see mxc://example.org/abc",
    ])
    func incompleteOrOtherUriIsText(key: String) {
        #expect(ReactionKeyKind(key: key) == .unicode(key))
        #expect(!ReactionKeyKind(key: key).isImage)
    }

    @Test(arguments: [
        "\u{1F44D}", // thumbs up
        "\u{2764}\u{FE0F}", // red heart with VS16
        "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", // ZWJ family
        "lgtm",
        "+1",
        "",
    ])
    func emojiAndPlainTextAreUnicode(key: String) {
        #expect(ReactionKeyKind(key: key) == .unicode(key))
    }

    @Test
    func colonNameIsAShortcode() {
        #expect(ReactionKeyKind(key: ":party_parrot:") == .shortcode("party_parrot"))
        #expect(ReactionKeyKind(key: ":+1:") == .shortcode("+1"))
    }

    @Test(arguments: [":", "::", ":a", "a:", ":a b:", ":a:b:", ":)"])
    func brokenShortcodeIsUnicode(key: String) {
        #expect(ReactionKeyKind(key: key) == .unicode(key))
    }

    @Test
    func spokenNames() {
        #expect(ReactionKeyKind(key: "mxc://example.org/abc").spokenName == "custom emoji")
        #expect(ReactionKeyKind(key: ":party_parrot:").spokenName == "party_parrot")
        #expect(ReactionKeyKind(key: "lgtm").spokenName == "lgtm")
    }
}

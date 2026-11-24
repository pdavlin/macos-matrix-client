import Foundation
@testable import Models
import Testing

/// MATRIX-234: a pick of the composer's emoji picker goes in place of the
/// selection. A custom emoji goes in as the token of a ":" completion pick
/// (MATRIX-156), so the send makes the same emoticon tag.
struct ComposerEmojiPickTests {
    private static let parrot = ImagePackEmoji(shortcode: "parrot", url: "mxc://example.org/parrot")

    private let packs = [
        ImagePack(key: "slack", displayName: "Work", emoji: [
            parrot,
            ImagePackEmoji(shortcode: "ship_it", url: "mxc://example.org/ship"),
        ]),
    ]

    private static let parrotTag =
        "<img data-mx-emoticon src=\"mxc://example.org/parrot\" alt=\":parrot:\" title=\":parrot:\" height=\"32\" />"

    private func caret(_ location: Int) -> NSRange {
        NSRange(location: location, length: 0)
    }

    /// The markdown that the send gives to the SDK for a draft text.
    private func sentMarkdown(_ draftText: String) -> String {
        MentionMarkdown.outgoingMessage(fromDraftText: draftText).resolvingEmoji(in: packs).markdown
    }

    // MARK: - Unicode

    @Test func unicodeGoesInAtTheCaret() throws {
        let edit = ComposerEmojiPick.unicode("👍").edit(in: "hi there", selection: caret(2))

        #expect(edit == ComposerTextEdit(range: caret(2), text: "👍"))
        #expect(try #require(edit.applied(to: "hi there")) == "hi👍 there")
        #expect(edit.caretAfter == 4)
    }

    @Test func unicodeReplacesTheSelection() throws {
        let selection = NSRange(location: 3, length: 5)
        let edit = ComposerEmojiPick.unicode("🎉").edit(in: "hi there!", selection: selection)

        #expect(try #require(edit.applied(to: "hi there!")) == "hi 🎉!")
        #expect(edit.caretAfter == 5)
    }

    @Test func unicodeGetsNoSpaceAfterALetter() {
        let edit = ComposerEmojiPick.unicode("👍").edit(in: "ok", selection: caret(2))
        #expect(edit.text == "👍")
    }

    // MARK: - Custom emoji

    @Test func customEmojiGoesInAsTheCompletionToken() throws {
        let edit = ComposerEmojiPick.custom(Self.parrot).edit(in: "hi ", selection: caret(3))

        #expect(edit.text == ComposerEmojiCompletion.insertion(for: Self.parrot))
        #expect(try #require(edit.applied(to: "hi ")) == "hi :parrot: ")
        #expect(edit.caretAfter == 12)
    }

    /// The draft and the sent markdown are the same as after a pick of the
    /// ":" completion list.
    @Test func customEmojiSendsTheSameTagAsACompletionPick() throws {
        let typed = "hi :par"
        let trigger = try #require(ComposerEmojiTrigger.find(in: typed, caret: (typed as NSString).length))
        let completion = try #require(ComposerEmojiCompletion.edit(for: Self.parrot, replacing: trigger).applied(to: typed))

        let picked = try #require(ComposerEmojiPick.custom(Self.parrot).edit(in: "hi ", selection: caret(3)).applied(to: "hi "))

        #expect(picked == completion)
        #expect(sentMarkdown(picked) == sentMarkdown(completion))
        #expect(sentMarkdown(picked) == "hi \(Self.parrotTag) ")
    }

    @Test func customEmojiReplacesTheSelection() throws {
        let text = "hi there"
        let edit = ComposerEmojiPick.custom(Self.parrot).edit(in: text, selection: NSRange(location: 3, length: 5))

        let result = try #require(edit.applied(to: text))
        #expect(result == "hi :parrot: ")
        #expect(sentMarkdown(result) == "hi \(Self.parrotTag) ")
    }

    /// The send keeps a token after a letter or a digit as text, so the
    /// pick puts a space before it.
    @Test func customEmojiAfterALetterOrADigitGetsASpace() throws {
        let afterLetter = try #require(ComposerEmojiPick.custom(Self.parrot).edit(in: "hi", selection: caret(2)).applied(to: "hi"))
        #expect(afterLetter == "hi :parrot: ")
        #expect(sentMarkdown(afterLetter) == "hi \(Self.parrotTag) ")

        let afterDigit = ComposerEmojiPick.custom(Self.parrot).edit(in: "x2", selection: caret(2))
        #expect(afterDigit.text == " :parrot: ")
    }

    @Test func customEmojiAtTheStartOrAfterPunctuationGetsNoSpace() {
        let pick = ComposerEmojiPick.custom(Self.parrot)
        #expect(pick.edit(in: "", selection: caret(0)).text == ":parrot: ")
        #expect(pick.edit(in: "hi", selection: caret(0)).text == ":parrot: ")
        #expect(pick.edit(in: "(", selection: caret(1)).text == ":parrot: ")
        #expect(pick.edit(in: "👍", selection: caret(2)).text == ":parrot: ")
        #expect(pick.edit(in: ":ship_it:", selection: caret(9)).text == ":parrot: ")
        // A mention chip is one attachment character in the text view.
        #expect(pick.edit(in: "\u{FFFC}", selection: caret(1)).text == ":parrot: ")
    }

    @Test func customEmojiAfterATokenWithNoSpaceStillResolves() throws {
        let text = ":ship_it:"
        let result = try #require(ComposerEmojiPick.custom(Self.parrot).edit(in: text, selection: caret(9)).applied(to: text))
        #expect(sentMarkdown(result).contains(Self.parrotTag))
        #expect(sentMarkdown(result).contains("alt=\":ship_it:\""))
    }

    // MARK: - From a picker cell

    @Test func aPackCellIsACustomPickWithItsShortcode() {
        let pack = ImagePack(key: "acme", displayName: nil, emoji: [
            ImagePackEmoji(shortcode: "shipit", url: "mxc://example.org/ship"),
            ImagePackEmoji(shortcode: "squirrel", url: "mxc://example.org/ship"),
        ])
        let entries = ImagePackSection(pack: pack).entries

        #expect(entries.map(ComposerEmojiPick.init(entry:)) == [
            .custom(ImagePackEmoji(shortcode: "shipit", url: "mxc://example.org/ship")),
            .custom(ImagePackEmoji(shortcode: "squirrel", url: "mxc://example.org/ship")),
        ])
        #expect(ComposerEmojiPick(entry: entries[1]).key == "mxc://example.org/ship")
    }

    @Test func aUnicodeCellIsAUnicodePick() {
        let entry = EmojiCatalog.Entry(value: "👍", name: "thumbs up", group: "People & Body", subgroup: "hand-fingers-closed")

        #expect(ComposerEmojiPick(entry: entry) == .unicode("👍"))
        #expect(ComposerEmojiPick(entry: entry).key == "👍")
    }

    // MARK: - Edit

    @Test func theCompletionEditReplacesTheQuery() throws {
        let trigger = ComposerEmojiTrigger(range: NSRange(location: 3, length: 4), query: "par")
        let edit = ComposerEmojiCompletion.edit(for: Self.parrot, replacing: trigger)

        #expect(edit == ComposerTextEdit(range: trigger.range, text: ":parrot: "))
        #expect(try #require(edit.applied(to: "hi :par")) == "hi :parrot: ")
    }

    @Test func anEditOutsideTheTextAppliesToNothing() {
        let edit = ComposerTextEdit(range: NSRange(location: 4, length: 2), text: "👍")
        #expect(edit.applied(to: "hi") == nil)
    }
}

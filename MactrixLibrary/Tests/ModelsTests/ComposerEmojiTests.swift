import Foundation
@testable import Models
import Testing

/// MATRIX-156: ":" opens the custom emoji completion list. The trigger, the
/// rows, and the selection are pure logic.
struct ComposerEmojiTests {
    private let packs = [
        ImagePack(key: "a", displayName: "Work", emoji: [
            ImagePackEmoji(shortcode: "apart", url: "mxc://a/apart"),
            ImagePackEmoji(shortcode: "parrot", url: "mxc://a/parrot"),
            ImagePackEmoji(shortcode: "party_parrot", url: "mxc://a/party"),
            ImagePackEmoji(shortcode: "ship_it", url: "mxc://a/ship"),
        ]),
        ImagePack(key: "b", displayName: "Other", emoji: [
            ImagePackEmoji(shortcode: "parrot", url: "mxc://b/parrot"),
            ImagePackEmoji(shortcode: "paris", url: "mxc://b/paris"),
        ]),
    ]

    private func trigger(_ text: String, caret: Int? = nil) -> ComposerEmojiTrigger? {
        ComposerEmojiTrigger.find(in: text, caret: caret ?? (text as NSString).length)
    }

    // MARK: - Trigger

    @Test func colonAndTwoLettersOpenTheList() {
        #expect(trigger(":pa") == ComposerEmojiTrigger(range: NSRange(location: 0, length: 3), query: "pa"))
        #expect(trigger("hi :par") == ComposerEmojiTrigger(range: NSRange(location: 3, length: 4), query: "par"))
        #expect(trigger("(:ship_it")?.query == "ship_it")
    }

    @Test func shortQueryDoesNotOpenTheList() {
        #expect(trigger(":") == nil)
        #expect(trigger(":p") == nil)
        #expect(trigger("hi :") == nil)
    }

    @Test func colonInsideAWordDoesNotOpenTheList() {
        #expect(trigger("10:30") == nil)
        #expect(trigger("https://example") == nil)
        #expect(trigger("note:pa") == nil)
    }

    @Test func queryStopsAtWhitespaceAndAtAClosedToken() {
        #expect(trigger(":pa rot") == nil)
        #expect(trigger(":parrot:") == nil)
        #expect(trigger(":parrot: ") == nil)
        #expect(trigger(":pa/x") == nil)
    }

    @Test func queryEndsAtTheCaret() {
        #expect(trigger("a :parrot b", caret: 5) == ComposerEmojiTrigger(range: NSRange(location: 2, length: 3), query: "pa"))
        #expect(trigger(":pa", caret: nil) != nil)
        #expect(ComposerEmojiTrigger.find(in: ":pa", caret: nil) == nil)
        #expect(ComposerEmojiTrigger.find(in: ":pa", caret: 9) == nil)
    }

    @Test func triggerAfterAChipOpensTheList() {
        #expect(trigger("\u{FFFC}:pa")?.query == "pa")
    }

    // MARK: - Rows

    @Test func prefixMatchesComeFirstAcrossPacks() {
        let names = ComposerEmojiCompletion.suggestions(for: "par", in: packs).map(\.shortcode)
        #expect(names == ["parrot", "party_parrot", "paris", "apart"])
    }

    @Test func sharedShortcodeShowsOnceWithTheFirstPackImage() throws {
        let rows = ComposerEmojiCompletion.suggestions(for: "parrot", in: packs)
        #expect(rows.map(\.shortcode) == ["parrot", "party_parrot"])
        let first = try #require(rows.first)
        #expect(first.url == "mxc://a/parrot")
        #expect(ComposerEmojiMarkup.shortcodeURLs(in: packs)["parrot"] == first.url)
    }

    @Test func searchIgnoresCase() {
        #expect(ComposerEmojiCompletion.suggestions(for: "SHIP", in: packs).map(\.shortcode) == ["ship_it"])
    }

    @Test func noPackAndNoMatchGiveNoRow() {
        #expect(ComposerEmojiCompletion.suggestions(for: "pa", in: []).isEmpty)
        #expect(ComposerEmojiCompletion.suggestions(for: "zz", in: packs).isEmpty)
    }

    @Test func limitCutsTheRows() {
        #expect(ComposerEmojiCompletion.suggestions(for: "pa", in: packs, limit: 2).map(\.shortcode) == ["parrot", "party_parrot"])
        #expect(ComposerEmojiCompletion.suggestions(for: "pa", in: packs, limit: 0).isEmpty)
    }

    @Test func pickInsertsTheTokenAndASpace() {
        let emoji = ImagePackEmoji(shortcode: "ship_it", url: "mxc://a/ship")
        #expect(ComposerEmojiCompletion.insertion(for: emoji) == ":ship_it: ")
    }

    // MARK: - State

    @Test func emptyListDoesNotOpen() throws {
        let open = try #require(trigger(":zz"))
        #expect(EmojiAutocompleteState(trigger: open, suggestions: []) == nil)
    }

    @Test func selectionMovesAndWraps() throws {
        let open = try #require(trigger(":pa"))
        let rows = ComposerEmojiCompletion.suggestions(for: open.query, in: packs)
        var state = try #require(EmojiAutocompleteState(trigger: open, suggestions: rows))
        #expect(state.selected.shortcode == "parrot")
        state.moveSelection(by: -1)
        #expect(state.selected.shortcode == "apart")
        state.moveSelection(by: 1)
        #expect(state.selected.shortcode == "parrot")
    }
}

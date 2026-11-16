import Foundation
import Models
import Testing

/// MATRIX-161: the rules of the emoji learned from message bodies.
struct LearnedEmojiTests {
    private func emoji(_ shortcode: String, _ media: String? = nil) -> ImagePackEmoji {
        ImagePackEmoji(shortcode: shortcode, url: "mxc://example.org/\(media ?? shortcode)")
    }

    // MARK: - The name and the source of a body emoticon

    @Test func theNameLosesItsColons() {
        #expect(LearnedEmoji.emoji(name: ":party_parrot:", url: "mxc://example.org/abc")
            == ImagePackEmoji(shortcode: "party_parrot", url: "mxc://example.org/abc"))
        #expect(LearnedEmoji.emoji(name: "shipit", url: "mxc://example.org/abc")?.shortcode == "shipit")
        #expect(LearnedEmoji.emoji(name: " :+1: ", url: "mxc://example.org/abc")?.shortcode == "+1")
    }

    @Test(arguments: ["", ":", "::", ": :", ":two words:", ":a:b:", ":a&amp;b:", ":<b>:", ":say\"hi\":", ":it's:"])
    func aNameThatCannotBeAShortcodeIsRefused(name: String) {
        #expect(LearnedEmoji.emoji(name: name, url: "mxc://example.org/abc") == nil)
    }

    @Test func aSourceThatIsNotAMatrixContentURLIsRefused() {
        #expect(LearnedEmoji.emoji(name: ":party:", url: "https://example.org/party.png") == nil)
        #expect(LearnedEmoji.emoji(name: ":party:", url: "") == nil)
    }

    // MARK: - The set

    @Test func recordsInTheOrderSeen() {
        var learned = LearnedEmoji()
        let changed1: Bool = learned.record(emoji("zebra"), imported: [])
        #expect(changed1)
        let changed2: Bool = learned.record(emoji("apple"), imported: [])
        #expect(changed2)
        #expect(learned.entries.map(\.shortcode) == ["zebra", "apple"])
    }

    @Test func theSameEmojiAgainChangesNothing() {
        var learned = LearnedEmoji(entries: [emoji("zebra"), emoji("apple")])
        let before = learned

        let changed3: Bool = learned.record(emoji("zebra"), imported: [])
        #expect(!changed3)
        #expect(learned == before)
    }

    @Test func anImportedShortcodeIsNotRecorded() {
        var learned = LearnedEmoji()
        let changed4: Bool = learned.record(emoji("parrot", "other"), imported: ["parrot"])
        #expect(!changed4)
        #expect(learned.entries.isEmpty)
    }

    @Test func aNewURLReplacesTheOldEntryAndIsTheNewest() {
        var learned = LearnedEmoji(entries: [emoji("zebra"), emoji("apple")])

        let changed5: Bool = learned.record(emoji("zebra", "v2"), imported: [])
        #expect(changed5)

        #expect(learned.entries == [emoji("apple"), emoji("zebra", "v2")])
    }

    @Test func theOldestIsDroppedOverTheCapacity() {
        var learned = LearnedEmoji()
        for number in 0 ..< LearnedEmoji.capacity + 2 {
            learned.record(emoji("e\(number)"), imported: [])
        }

        #expect(learned.entries.count == LearnedEmoji.capacity)
        #expect(learned.entries.first?.shortcode == "e2")
        #expect(learned.entries.last?.shortcode == "e\(LearnedEmoji.capacity + 1)")
        // A dropped emoji is new again.
        let changed6: Bool = learned.record(emoji("e0"), imported: [])
        #expect(changed6)
    }

    @Test func anEntryIsDroppedOnceTheImportHasIt() {
        var learned = LearnedEmoji(entries: [emoji("zebra"), emoji("apple"), emoji("mango")])

        let changed7: Bool = learned.remove(imported: ["apple", "parrot"])
        #expect(changed7)
        #expect(learned.entries.map(\.shortcode) == ["zebra", "mango"])
        let changed8: Bool = learned.remove(imported: ["apple", "parrot"])
        #expect(!changed8)
        // The dropped shortcode can be learned again if the import loses it.
        let changed9: Bool = learned.record(emoji("apple"), imported: [])
        #expect(changed9)
    }

    @Test func storedEntriesKeepTheLastOfAShortcodeAndTheNewestOverTheCapacity() {
        let stored = [emoji("zebra"), emoji("apple"), emoji("zebra", "v2")]
        #expect(LearnedEmoji(entries: stored).entries == [emoji("apple"), emoji("zebra", "v2")])

        let many = (0 ..< LearnedEmoji.capacity + 5).map { emoji("e\($0)") }
        #expect(LearnedEmoji(entries: many).entries.first?.shortcode == "e5")
    }

    // MARK: - The packs shown

    @Test func learnedEmojiGoIntoTheFirstImportedPackInShortcodeOrder() {
        let first = ImagePack(key: "acme", displayName: "Acme emojis", emoji: [emoji("parrot"), emoji("shipit")])
        let second = ImagePack(key: "other", displayName: "Other", emoji: [emoji("blob")])

        let shown = ImagePack.merging(learned: [emoji("zebra"), emoji("Apple")], into: [first, second], fallbackName: "Acme")

        #expect(shown.map(\.key) == ["acme", "other"])
        #expect(shown[0].displayName == "Acme emojis")
        #expect(shown[0].emoji.map(\.shortcode) == ["Apple", "parrot", "shipit", "zebra"])
        #expect(shown[1] == second)
    }

    @Test func learnedEmojiWithNoImportAreOnePackNamedAfterTheSpace() {
        let shown = ImagePack.merging(learned: [emoji("zebra"), emoji("apple")], into: [], fallbackName: "Acme")

        #expect(shown.count == 1)
        #expect(shown.first?.key == ImagePack.learnedKey)
        #expect(shown.first?.displayName == "Acme")
        #expect(shown.first?.emoji.map(\.shortcode) == ["apple", "zebra"])
    }

    @Test func noLearnedEmojiLeavesThePacksAsTheyAre() {
        let pack = ImagePack(key: "acme", displayName: nil, emoji: [emoji("parrot")])
        #expect(ImagePack.merging(learned: [], into: [pack], fallbackName: "Acme") == [pack])
        #expect(ImagePack.merging(learned: [], into: [], fallbackName: "Acme").isEmpty)
    }

    // MARK: - The composer's open list

    @Test func theOpenListKeepsItsSelectedRowWhenTheRowsChange() throws {
        var state = try #require(ComposerAutocompleteState(trigger: "pa", suggestions: ["parrot", "party"]))
        state.moveSelection(by: 1)

        let updated = try #require(state.replacing(suggestions: ["pager", "parrot", "party"]))
        #expect(updated.selected == "party")
        #expect(updated.trigger == "pa")

        let without = try #require(state.replacing(suggestions: ["pager", "parrot"]))
        #expect(without.selected == "pager")
        #expect(state.replacing(suggestions: []) == nil)
    }
}

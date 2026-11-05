import Models
import Testing

/// MATRIX-111 (M2-B4): the reaction picker's emoji list, search, and arrow
/// keys.
struct EmojiCatalogTests {
    /// A small file in the generated format, with two groups.
    static let fixture = """
    # Emoji 15.1, test fixture.
    G\tSmileys & Emotion
    S\tface-smiling
    😀\tgrinning face
    😂\tface with tears of joy
    S\tface-affection
    😍\tsmiling face with heart-eyes
    G\tPeople & Body
    S\thand-fingers-closed
    👍\tthumbs up
    👎\tthumbs down
    👊\toncoming fist
    G\tFlags
    S\tcountry-flag
    🇨🇮\tflag: Côte d’Ivoire
    """

    let catalog = EmojiCatalog.parse(Self.fixture)

    private func values(_ entries: [EmojiCatalog.Entry]) -> [String] {
        entries.map(\.value)
    }

    // MARK: - Parsing

    @Test func parsesGroupsInOrder() {
        #expect(catalog.categories.map(\.name) == ["Smileys & Emotion", "People & Body", "Flags"])
        #expect(values(catalog.entries) == ["😀", "😂", "😍", "👍", "👎", "👊", "🇨🇮"])
    }

    @Test func entryKeepsNameGroupAndSubgroup() throws {
        let thumbsUp = try #require(catalog.entry(for: "👍"))
        #expect(thumbsUp.name == "thumbs up")
        #expect(thumbsUp.group == "People & Body")
        #expect(thumbsUp.subgroup == "hand-fingers-closed")
    }

    @Test func skipsLinesThatDoNotFit() {
        let parsed = EmojiCatalog.parse("😀\tbefore any group\nG\tOnly\nnot a record\nS\tsub\n🙂\tslightly smiling face\n")
        #expect(parsed.categories.map(\.name) == ["Only"])
        #expect(values(parsed.entries) == ["🙂"])
    }

    @Test func keepsTheKeycapThatStartsWithAHash() {
        // "#️⃣" starts with "#", but only "# " opens a comment.
        let parsed = EmojiCatalog.parse("# comment\nG\tSymbols\nS\tkeycap\n#️⃣\tkeycap: #\n")
        #expect(values(parsed.entries) == ["#️⃣"])
    }

    // MARK: - Search

    @Test func searchMatchesTheStartOfTheName() {
        #expect(values(catalog.search("thumbs")) == ["👍", "👎"])
    }

    @Test func searchRanksTheExactNameFirst() {
        #expect(values(catalog.search("thumbs down")) == ["👎"])
        #expect(values(catalog.search("thumbs up")).first == "👍")
    }

    @Test func searchMatchesWordsInAnyOrder() {
        #expect(values(catalog.search("up thumbs")) == ["👍"])
        #expect(values(catalog.search("joy")) == ["😂"])
    }

    @Test func searchIgnoresCaseAndDiacritics() {
        #expect(values(catalog.search("THUMBS")) == ["👍", "👎"])
        #expect(values(catalog.search("Thumbs Up")) == ["👍"])
        #expect(values(catalog.search("cote")) == ["🇨🇮"])
    }

    @Test func searchFindsKeywordsAfterNameMatches() {
        // "fingers" is in no name, only in the subgroup of the three hands,
        // so all three match as keywords, in catalog order.
        #expect(values(catalog.search("fingers")) == ["👍", "👎", "👊"])
        // "smiling" starts a name word of 😍 and is a keyword of 😀 and 😂.
        #expect(values(catalog.search("smiling")) == ["😍", "😀", "😂"])
    }

    @Test func searchNeedsEveryWord() {
        #expect(catalog.search("thumbs sideways").isEmpty)
        #expect(catalog.search("zzz").isEmpty)
    }

    @Test func blankQueryMatchesNothing() {
        #expect(catalog.search("").isEmpty)
        #expect(catalog.search("  ").isEmpty)
    }

    // MARK: - Picker content

    @Test func emptyQueryShowsEveryCategory() {
        let content = EmojiPickerContent(catalog: catalog, query: "")
        #expect(!content.isSearch)
        #expect(content.sections.map(\.title) == ["Smileys & Emotion", "People & Body", "Flags"])
        #expect(content.sections.map(\.startIndex) == [0, 3, 6])
        #expect(content.entries.count == 7)
    }

    @Test func queryShowsOneUntitledResultSection() {
        let content = EmojiPickerContent(catalog: catalog, query: "thumbs")
        #expect(content.isSearch)
        #expect(content.sections.map(\.title) == [nil])
        #expect(values(content.entries) == ["👍", "👎"])
        #expect(EmojiPickerContent(catalog: catalog, query: "zzz").sections.isEmpty)
    }

    @Test func returnPicksTheFirstMatchUntilAnArrowMoves() {
        let content = EmojiPickerContent(catalog: catalog, query: "thumbs")
        #expect(content.effectiveSelection(nil) == 0)
        #expect(content.effectiveSelection(1) == 1)
        // A selection past the end, left from a longer list, falls back.
        #expect(content.effectiveSelection(5) == 0)
        #expect(EmojiPickerContent(catalog: catalog, query: "zzz").effectiveSelection(nil) == nil)
    }

    @Test func leftAndRightStepAndStopAtTheEnds() {
        let content = EmojiPickerContent(catalog: catalog, query: "")
        #expect(content.index(after: .right, from: 2, columns: 2) == 3)
        #expect(content.index(after: .left, from: 3, columns: 2) == 2)
        #expect(content.index(after: .left, from: 0, columns: 2) == 0)
        #expect(content.index(after: .right, from: 6, columns: 2) == 6)
    }

    @Test func upAndDownKeepTheColumnAcrossSections() {
        // Two columns. Rows: [0 1] [2] | [3 4] [5] | [6]
        let content = EmojiPickerContent(catalog: catalog, query: "")
        #expect(content.index(after: .down, from: 1, columns: 2) == 2)
        #expect(content.index(after: .down, from: 2, columns: 2) == 3)
        #expect(content.index(after: .down, from: 4, columns: 2) == 5)
        #expect(content.index(after: .up, from: 4, columns: 2) == 2)
        #expect(content.index(after: .up, from: 3, columns: 2) == 2)
        #expect(content.index(after: .up, from: 1, columns: 2) == 1)
        #expect(content.index(after: .down, from: 6, columns: 2) == 6)
    }

    @Test func arrowsDoNothingInAnEmptyGrid() {
        let content = EmojiPickerContent(catalog: catalog, query: "zzz")
        #expect(content.index(after: .down, from: 0, columns: 9) == nil)
    }
}

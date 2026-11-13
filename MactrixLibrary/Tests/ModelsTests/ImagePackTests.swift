import Foundation
import Models
import Testing

/// Room state in the shape that mautrix-slack writes (MATRIX-155): the
/// content of `event.ImagePackEventContent` (mautrix-go `event/imagepack.go`)
/// and, for a large pack, the parts of `provisionutil.SplitPack`.
enum ImagePackFixtures {
    /// A workspace space with one small pack, between other state events.
    static let onePack = """
    [
      {"type": "m.room.create", "state_key": "", "sender": "@slackbot:example.org",
       "content": {"type": "m.space", "room_version": "11"}},
      {"type": "m.room.name", "state_key": "", "content": {"name": "Acme"}},
      {"type": "m.space.child", "state_key": "!channel:example.org", "content": {"via": ["example.org"]}},
      {"type": "m.room.member", "state_key": "@user:example.org", "content": {"membership": "join", "images": 3}},
      {"type": "m.room.image_pack", "state_key": "acme", "sender": "@slackbot:example.org",
       "event_id": "$pack", "origin_server_ts": 1794000000000,
       "content": {
         "images": {
           "shipit": {"url": "mxc://example.org/shipit"},
           "party_parrot": {"url": "mxc://example.org/parrot"},
           "Parrot-Wave": {"url": "mxc://example.org/wave"},
           "acme": {"url": "mxc://example.org/acme", "body": "Acme logo", "info": {"w": 128, "h": 128}},
           "linked": {"url": "https://emoji.slack-edge.com/T1/linked/abc.png"},
           "no_url": {"body": "nothing"},
           "wrong_type": 7
         },
         "pack": {
           "display_name": "Acme emojis",
           "avatar_url": "mxc://example.org/avatar",
           "usage": ["emoticon"],
           "attribution": "Imported from Slack workspace https://acme.slack.com/",
           "fi.mau.bridged_pack": {"network": "slack", "url": "https://acme.slack.com/"}
         }
       }}
    ]
    """

    /// A pack in three parts, out of order, plus one part of an older import
    /// that had four parts.
    static let splitPack = """
    [
      {"type": "m.room.image_pack", "state_key": "acme.002",
       "content": {
         "images": {"zebra": {"url": "mxc://example.org/zebra"}, "yak": {"url": "mxc://example.org/yak"}},
         "pack": {"display_name": "Acme emojis (part 3)", "usage": ["emoticon"]},
         "fi.mau.combined_pack_key": "acme", "fi.mau.combined_pack_index": 2, "fi.mau.combined_pack_count": 3}},
      {"type": "m.room.image_pack", "state_key": "acme.003",
       "content": {
         "images": {"stale": {"url": "mxc://example.org/stale"}},
         "pack": {"display_name": "Acme emojis (part 4)", "usage": ["emoticon"]},
         "fi.mau.combined_pack_key": "acme", "fi.mau.combined_pack_index": 3, "fi.mau.combined_pack_count": 4}},
      {"type": "m.room.image_pack", "state_key": "acme",
       "content": {
         "images": {"aardvark": {"url": "mxc://example.org/aardvark"}, "bee": {"url": "mxc://example.org/bee"}},
         "pack": {"display_name": "Acme emojis (part 1)", "usage": ["emoticon"]},
         "fi.mau.combined_pack_key": "acme", "fi.mau.combined_pack_index": 0, "fi.mau.combined_pack_count": 3}},
      {"type": "m.room.image_pack", "state_key": "acme.001",
       "content": {
         "images": {"moose": {"url": "mxc://example.org/moose"}, "bee": {"url": "mxc://example.org/second-bee"}},
         "pack": {"display_name": "Acme emojis (part 2)", "usage": ["emoticon"]},
         "fi.mau.combined_pack_key": "acme", "fi.mau.combined_pack_index": 1, "fi.mau.combined_pack_count": 3}}
    ]
    """

    static func data(_ json: String) -> Data {
        Data(json.utf8)
    }
}

/// MATRIX-155: the parser for `m.room.image_pack` state.
struct ImagePackParserTests {
    @Test func readsOnePackSortedByShortcode() throws {
        let packs = try ImagePack.parse(roomState: ImagePackFixtures.data(ImagePackFixtures.onePack))

        #expect(packs.count == 1)
        let pack = try #require(packs.first)
        #expect(pack.key == "acme")
        #expect(pack.displayName == "Acme emojis")
        #expect(pack.emoji == [
            ImagePackEmoji(shortcode: "acme", url: "mxc://example.org/acme"),
            ImagePackEmoji(shortcode: "Parrot-Wave", url: "mxc://example.org/wave"),
            ImagePackEmoji(shortcode: "party_parrot", url: "mxc://example.org/parrot"),
            ImagePackEmoji(shortcode: "shipit", url: "mxc://example.org/shipit"),
        ])
    }

    @Test func joinsThePartsOfASplitPackInIndexOrder() throws {
        let packs = try ImagePack.parse(roomState: ImagePackFixtures.data(ImagePackFixtures.splitPack))

        #expect(packs.count == 1)
        let pack = try #require(packs.first)
        #expect(pack.key == "acme")
        #expect(pack.displayName == "Acme emojis")
        #expect(pack.emoji.map(\.shortcode) == ["aardvark", "bee", "moose", "yak", "zebra"])
        // The first part wins a shortcode that two parts have.
        #expect(pack.emoji[1].url == "mxc://example.org/bee")
    }

    @Test func anUnsplitPackReplacesThePartsOfAnOlderImport() throws {
        let json = """
        [
          {"type": "m.room.image_pack", "state_key": "acme",
           "content": {"images": {"new": {"url": "mxc://example.org/new"}}, "pack": {"display_name": "Acme emojis"}}},
          {"type": "m.room.image_pack", "state_key": "acme.001",
           "content": {"images": {"old": {"url": "mxc://example.org/old"}},
                       "pack": {"display_name": "Acme emojis (part 2)"},
                       "fi.mau.combined_pack_key": "acme", "fi.mau.combined_pack_index": 1,
                       "fi.mau.combined_pack_count": 2}}
        ]
        """
        let packs = try ImagePack.parse(roomState: ImagePackFixtures.data(json))

        #expect(packs.map(\.key) == ["acme"])
        #expect(packs.first?.emoji.map(\.shortcode) == ["new"])
    }

    @Test func keepsTwoPacksApartSortedByKey() throws {
        let json = """
        [
          {"type": "m.room.image_pack", "state_key": "zeta",
           "content": {"images": {"z": {"url": "mxc://example.org/z"}}}},
          {"type": "m.room.image_pack", "state_key": "alpha",
           "content": {"images": {"a": {"url": "mxc://example.org/a"}}, "pack": {"display_name": ""}}}
        ]
        """
        let packs = try ImagePack.parse(roomState: ImagePackFixtures.data(json))

        #expect(packs.map(\.key) == ["alpha", "zeta"])
        #expect(packs.map(\.displayName) == [nil, nil])
    }

    @Test func leavesOutStickersAndEmptyPacks() throws {
        let json = """
        [
          {"type": "m.room.image_pack", "state_key": "stickers",
           "content": {"images": {"cat": {"url": "mxc://example.org/cat"}}, "pack": {"usage": ["sticker"]}}},
          {"type": "m.room.image_pack", "state_key": "mixed",
           "content": {"images": {
             "sticker_only": {"url": "mxc://example.org/s", "usage": ["sticker"]},
             "both": {"url": "mxc://example.org/b", "usage": ["sticker", "emoticon"]},
             "plain": {"url": "mxc://example.org/p"}}}},
          {"type": "m.room.image_pack", "state_key": "removed", "content": {}},
          {"type": "im.ponies.room_emotes", "state_key": "old",
           "content": {"images": {"pony": {"url": "mxc://example.org/pony"}}}}
        ]
        """
        let packs = try ImagePack.parse(roomState: ImagePackFixtures.data(json))

        #expect(packs.map(\.key) == ["mixed"])
        #expect(packs.first?.emoji.map(\.shortcode) == ["both", "plain"])
    }

    @Test func aRoomWithNoPackGivesNoPacks() throws {
        let json = """
        [{"type": "m.room.name", "state_key": "", "content": {"name": "Acme"}}]
        """
        #expect(try ImagePack.parse(roomState: ImagePackFixtures.data(json)).isEmpty)
        #expect(try ImagePack.parse(roomState: ImagePackFixtures.data("[]")).isEmpty)
    }

    @Test func aBodyThatIsNotAnEventArrayThrows() {
        let errorBody = """
        {"errcode": "M_FORBIDDEN", "error": "You are not a member"}
        """
        #expect(throws: ImagePack.MalformedRoomState.self) {
            try ImagePack.parse(roomState: ImagePackFixtures.data(errorBody))
        }
        #expect(throws: ImagePack.MalformedRoomState.self) {
            try ImagePack.parse(roomState: ImagePackFixtures.data("not json"))
        }
    }

    @Test func aPackWithoutANameTakesTheFallbackName() {
        let emoji = [ImagePackEmoji(shortcode: "a", url: "mxc://example.org/a")]
        let unnamed = ImagePack(key: "k", displayName: nil, emoji: emoji)
        let named = ImagePack(key: "k", displayName: "Acme emojis", emoji: emoji)

        #expect(unnamed.named(fallback: "Acme").displayName == "Acme")
        #expect(unnamed.named(fallback: nil).displayName == nil)
        #expect(named.named(fallback: "Acme").displayName == "Acme emojis")
    }

    @Test func tellsAnImageKeyFromAUnicodeEmoji() {
        #expect(ImagePack.isImageKey("mxc://example.org/parrot"))
        #expect(!ImagePack.isImageKey("🎉"))
        #expect(!ImagePack.isImageKey(":party_parrot:"))
    }
}

/// MATRIX-155: the shortcode search.
struct ImagePackSearchTests {
    private let pack = ImagePack(
        key: "acme",
        displayName: "Acme emojis",
        emoji: ["acme", "dancing_parrot", "Parrot-Wave", "party_parrot", "shipit"].map {
            ImagePackEmoji(shortcode: $0, url: "mxc://example.org/\($0)")
        }
    )

    @Test func prefixMatchesComeBeforeTheOtherMatches() {
        #expect(pack.search("parrot").map(\.shortcode) == ["Parrot-Wave", "dancing_parrot", "party_parrot"])
        #expect(pack.search("par").map(\.shortcode) == ["Parrot-Wave", "party_parrot", "dancing_parrot"])
    }

    @Test func caseAndColonsDoNotMatter() {
        #expect(pack.search("SHIP").map(\.shortcode) == ["shipit"])
        #expect(pack.search(":shipit:").map(\.shortcode) == ["shipit"])
        #expect(pack.search("  wave ").map(\.shortcode) == ["Parrot-Wave"])
    }

    @Test func aBlankOrUnknownQueryMatchesNothing() {
        #expect(pack.search("").isEmpty)
        #expect(pack.search(" : ").isEmpty)
        #expect(pack.search("zzz").isEmpty)
    }
}

/// MATRIX-155: the pack as a section of the reaction picker's grid.
struct ImagePackPickerContentTests {
    private let catalog = EmojiCatalog.parse("""
    G\tSmileys & Emotion
    S\tface-smiling
    😀\tgrinning face
    😃\tgrinning face with big eyes
    G\tAnimals & Nature
    S\tanimal-bird
    🦜\tparrot
    """)

    private let packs = [
        ImagePackSection(pack: ImagePack(
            key: "acme",
            displayName: "Acme emojis",
            emoji: [
                ImagePackEmoji(shortcode: "alias_parrot", url: "mxc://example.org/parrot"),
                ImagePackEmoji(shortcode: "party_parrot", url: "mxc://example.org/parrot"),
                ImagePackEmoji(shortcode: "shipit", url: "mxc://example.org/shipit"),
            ]
        )),
    ]

    @Test func thePackSectionComesBeforeTheUnicodeCategories() {
        let content = EmojiPickerContent(catalog: catalog, packs: packs, query: "")

        #expect(content.sections.map(\.title) == ["Acme emojis", "Smileys & Emotion", "Animals & Nature"])
        #expect(content.sections.map(\.startIndex) == [0, 3, 5])
        #expect(content.entries.prefix(3).map(\.value) == [
            "mxc://example.org/parrot", "mxc://example.org/parrot", "mxc://example.org/shipit",
        ])
        #expect(content.entries.prefix(3).map(\.name) == ["alias_parrot", "party_parrot", "shipit"])
        #expect(content.entries.prefix(3).map(\.isImage) == [true, true, true])
        #expect(!content.entries[3].isImage)
    }

    @Test func twoShortcodesOfOneImageHaveDifferentIds() {
        let content = EmojiPickerContent(catalog: catalog, packs: packs, query: "")
        #expect(Set(content.entries.map(\.id)).count == content.entries.count)
    }

    @Test func aPackWithoutANameHasTheGenericTitle() {
        let section = ImagePackSection(pack: ImagePack(key: "k", displayName: nil, emoji: []))
        #expect(section.title == ImagePackSection.untitled)
    }

    @Test func noPackGivesTheSameContentAsBefore() {
        #expect(EmojiPickerContent(catalog: catalog, packs: [], query: "") == EmojiPickerContent(catalog: catalog, query: ""))
        let emptyPack = [ImagePackSection(pack: ImagePack(key: "k", displayName: "Empty", emoji: []))]
        #expect(EmojiPickerContent(catalog: catalog, packs: emptyPack, query: "").sections.map(\.title) == [
            "Smileys & Emotion", "Animals & Nature",
        ])
    }

    @Test func aSearchShowsUnicodeMatchesThenThePackMatches() {
        let content = EmojiPickerContent(catalog: catalog, packs: packs, query: "parrot")

        #expect(content.sections.map(\.title) == [nil, "Acme emojis"])
        #expect(content.entries.map(\.name) == ["parrot", "alias_parrot", "party_parrot"])
        // Return picks the first entry: the Unicode match.
        #expect(content.effectiveSelection(nil) == 0)
    }

    @Test func aSearchWithOnlyPackMatchesSelectsThePackEmoji() throws {
        let content = EmojiPickerContent(catalog: catalog, packs: packs, query: "ship")

        #expect(content.sections.map(\.title) == ["Acme emojis"])
        let selected = try #require(content.effectiveSelection(nil))
        #expect(content.entries[selected].value == "mxc://example.org/shipit")
    }

    @Test func arrowKeysCrossThePackSection() {
        let content = EmojiPickerContent(catalog: catalog, packs: packs, query: "")

        // Two columns: the pack is rows [0, 1] and [2], then 😀 😃, then 🦜.
        #expect(content.index(after: .down, from: 0, columns: 2) == 2)
        #expect(content.index(after: .down, from: 1, columns: 2) == 2)
        #expect(content.index(after: .down, from: 2, columns: 2) == 3)
        #expect(content.index(after: .up, from: 4, columns: 2) == 2)
        #expect(content.index(after: .up, from: 3, columns: 2) == 2)
        #expect(content.index(after: .right, from: 2, columns: 2) == 3)
        #expect(content.index(after: .left, from: 3, columns: 2) == 2)
        #expect(content.index(after: .left, from: 0, columns: 2) == 0)
    }
}

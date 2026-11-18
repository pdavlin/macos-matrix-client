import Foundation
import Models
import Testing

/// MATRIX-191: the title of a Spotify link from the homeserver's URL
/// preview. The fixtures are the answers of the dev homeserver on
/// 2026-11-18.
struct MusicLinkTitleTests {
    /// The body for `https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=abc`,
    /// byte for byte, cut into lines here only.
    static let trackJSON = #"{"og:url": "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT", "#
        + #""og:title": "Never Gonna Give You Up", "og:site_name": "Spotify", "#
        + #""og:description": "Rick Astley · Whenever You Need Somebody · Song · 1987", "og:type": "music.song", "#
        + #""og:audio": "...", "og:image:width": "640", "og:image:height": "640"}"#

    /// The body for `https://open.spotify.com/album/6N9PS4QXF1D0OWPk0Sxtb4`.
    static let albumJSON = #"{"og:url": "https://open.spotify.com/album/6N9PS4QXF1D0OWPk0Sxtb4", "#
        + #""og:title": "Listen to Whenever You Need Somebody - Album by Rick Astley | Spotify", "og:site_name": "Spotify", "#
        + #""og:description": "Rick Astley · album · 1987 · 10 songs", "og:type": "music.album", "#
        + #""og:image:width": "640", "og:image:height": "640"}"#

    private func parse(_ json: String, _ kind: MusicLink.Kind) -> MusicLinkTitle? {
        MusicLinkTitle.parse(Data(json.utf8), kind: kind)
    }

    private func album(title: String, description: String = "Rick Astley · album · 1987 · 10 songs") throws -> MusicLinkTitle? {
        let object: [String: String] = ["og:type": "music.album", "og:title": title, "og:description": description]
        return try MusicLinkTitle.parse(JSONSerialization.data(withJSONObject: object), kind: .album)
    }

    @Test func aTrackGivesArtistAndSong() throws {
        let title = try #require(parse(Self.trackJSON, .song))
        #expect(title == MusicLinkTitle(artist: "Rick Astley", name: "Never Gonna Give You Up"))
        #expect(title.text == "Rick Astley \u{00B7} Never Gonna Give You Up")
    }

    @Test func anAlbumGivesArtistAndAlbum() throws {
        let title = try #require(parse(Self.albumJSON, .album))
        #expect(title == MusicLinkTitle(artist: "Rick Astley", name: "Whenever You Need Somebody"))
        #expect(title.text == "Rick Astley \u{00B7} Whenever You Need Somebody")
    }

    @Test func anAlbumTitleWithNoPatternAndNoSpotifySuffixIsTheNameAsItIs() throws {
        #expect(try album(title: "Whenever You Need Somebody")?.name == "Whenever You Need Somebody")
    }

    @Test func anAlbumTitleWithTheSuffixButNoPatternHasNoTitle() throws {
        #expect(try album(title: "Whenever You Need Somebody | Spotify") == nil)
        #expect(try album(title: "Listen to Whenever You Need Somebody | Spotify") == nil)
    }

    @Test func anAlbumNameThatHoldsTheSeparatorKeepsIt() throws {
        let title = try album(title: "Listen to Live - Album by Night - Album by Rick Astley | Spotify")
        #expect(title?.name == "Live - Album by Night")
    }

    @Test func aSingleAndAnEPAreAlbums() throws {
        #expect(try album(title: "Listen to One Song - Single by Rick Astley | Spotify")?.name == "One Song")
        #expect(try album(title: "Listen to Four Songs - EP by Rick Astley | Spotify")?.name == "Four Songs")
    }

    @Test func severalArtistsKeepTheirText() throws {
        let title = try album(
            title: "Listen to Duets - Album by Ann, Bob | Spotify",
            description: "Ann, Bob · album · 2020 · 2 songs"
        )
        #expect(title == MusicLinkTitle(artist: "Ann, Bob", name: "Duets"))
    }

    @Test func anEmptyAlbumNameHasNoTitle() throws {
        #expect(try album(title: "Listen to  - Album by Rick Astley | Spotify") == nil)
        #expect(try album(title: "   ") == nil)
    }

    @Test(arguments: ["og:title", "og:description", "og:type"])
    func aMissingKeyHasNoTitle(key: String) throws {
        var object = try #require(JSONSerialization.jsonObject(with: Data(Self.trackJSON.utf8)) as? [String: Any])
        object[key] = nil
        #expect(try MusicLinkTitle.parse(JSONSerialization.data(withJSONObject: object), kind: .song) == nil)
    }

    @Test func anEmptyArtistHasNoTitle() throws {
        let object = ["og:type": "music.song", "og:title": "Song", "og:description": " · Song · 1987"]
        #expect(try MusicLinkTitle.parse(JSONSerialization.data(withJSONObject: object), kind: .song) == nil)
    }

    @Test func aPageOfAnotherTypeHasNoTitle() {
        #expect(parse(Self.trackJSON, .album) == nil)
        #expect(parse(Self.albumJSON, .song) == nil)
        let website = #"{"og:type": "website", "og:title": "Spotify", "og:description": "Spotify is a digital music service"}"#
        #expect(parse(website, .song) == nil)
    }

    @Test func aBodyThatIsNotAnObjectHasNoTitle() {
        #expect(parse("[]", .song) == nil)
        #expect(parse("not json", .song) == nil)
        #expect(parse("", .song) == nil)
    }
}

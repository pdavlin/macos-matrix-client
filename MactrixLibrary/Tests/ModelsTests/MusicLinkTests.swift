import Foundation
import Models
import Testing

/// MATRIX-178: the music link classifier and the song.link target.
struct MusicLinkTests {
    /// A real 22-character Spotify ID (research note A3).
    static let track = "4cOdK2wGLETKBW3PvgPWqT"
    static let album = "1A2GTWGtFfWp7KSQTwWOyo"

    // MARK: Spotify

    @Test(arguments: [
        "https://open.spotify.com/track/\(track)",
        "http://open.spotify.com/track/\(track)",
        "https://OPEN.SPOTIFY.COM/track/\(track)",
        "https://open.spotify.com/track/\(track)/",
        "https://open.spotify.com/track/\(track)?si=0123456789abcdef",
        "https://open.spotify.com/track/\(track)?si=abc&nd=1&context=spotify%3Aplaylist%3A37i9dQZF1DXcBWIGoYBM5M",
        "https://open.spotify.com/track/\(track)?utm_source=copy-link&utm_medium=copy-link",
        "https://open.spotify.com/intl-de/track/\(track)",
        "https://open.spotify.com/intl-pt-BR/track/\(track)?si=xyz",
        "https://open.spotify.com/track/\(track)#fragment",
        "spotify:track:\(track)",
    ])
    func spotifyTrackIsASong(_ string: String) throws {
        let link = try #require(MusicLink.classify(string))
        #expect(link.service == .spotify)
        #expect(link.kind == .song)
        #expect(link.canonicalURL.absoluteString == "https://open.spotify.com/track/\(Self.track)")
    }

    @Test(arguments: [
        "https://open.spotify.com/album/\(album)",
        "https://open.spotify.com/album/\(album)?si=0123456789abcdef",
        "https://open.spotify.com/intl-ja/album/\(album)",
        "spotify:album:\(album)",
    ])
    func spotifyAlbumIsAnAlbum(_ string: String) throws {
        let link = try #require(MusicLink.classify(string))
        #expect(link.service == .spotify)
        #expect(link.kind == .album)
        #expect(link.canonicalURL.absoluteString == "https://open.spotify.com/album/\(Self.album)")
    }

    @Test(arguments: [
        "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M",
        "https://open.spotify.com/artist/0gxyHStUsqpMadRV0Di1Qt",
        "https://open.spotify.com/show/2mTUnDkuKUkhiueKcVWoP0",
        "https://open.spotify.com/episode/512ojhOuo1ktJprKbVcKyQ",
        "https://open.spotify.com/user/spotify",
        "https://open.spotify.com/intl-de/playlist/37i9dQZF1DXcBWIGoYBM5M",
        "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M",
        "spotify:artist:0gxyHStUsqpMadRV0Di1Qt",
        "spotify:episode:512ojhOuo1ktJprKbVcKyQ",
        "spotify:user:spotify",
    ])
    func spotifyOtherTypesStay(_ string: String) {
        #expect(MusicLink.classify(string) == nil)
    }

    /// The type of a short link is not known without a request.
    @Test(arguments: [
        "https://spotify.link/AbCdEfGhIjK",
        "https://spotify.app.link/AbCdEfGhIjK",
        "https://spotify.app.link/AbCdEfGhIjK?_p=c41",
        "https://deezer.page.link/AbCdEfGh",
    ])
    func shortLinksStay(_ string: String) {
        #expect(MusicLink.classify(string) == nil)
    }

    @Test(arguments: [
        // Too short, too long, not base62.
        "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWq",
        "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqTx",
        "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPW-T",
        // Extra path segments.
        "https://open.spotify.com/embed/track/\(track)",
        "https://open.spotify.com/track/\(track)/extra",
        "https://open.spotify.com/track",
        "https://open.spotify.com/",
        "https://evil.example/open.spotify.com/track/\(track)",
        "https://open.spotify.com.evil.example/track/\(track)",
        "spotify:track",
        "spotify:track:\(track):extra",
        "ftp://open.spotify.com/track/\(track)",
    ])
    func malformedSpotifyStays(_ string: String) {
        #expect(MusicLink.classify(string) == nil)
    }

    // MARK: Apple Music and other URLs

    @Test(arguments: [
        "https://music.apple.com/us/album/never-gonna-give-you-up/1559885420?i=1559885421",
        "https://music.apple.com/us/album/never-gonna-give-you-up/1559885420",
        "https://itunes.apple.com/us/album/kitchen/1443108737?i=1443109064",
        "https://song.link/https://open.spotify.com/track/\(track)",
        "https://album.link/s/\(album)",
        "https://example.org/track/123",
        "https://matrix.to/#/!room:example.org",
        "mailto:someone@example.org",
        "not a url",
        "",
    ])
    func otherLinksStay(_ string: String) {
        #expect(MusicLink.classify(string) == nil)
    }

    /// Services the table leaves out: the URL either needs its query to name
    /// the item, or does not tell a song from a playlist.
    @Test(arguments: [
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://music.youtube.com/playlist?list=OLAK5uy_abc",
        "https://music.amazon.com/albums/B00000000?trackAsin=B00000001",
        "https://music.amazon.com/albums/B00000000",
        "https://soundcloud.com/rick-astley-official/never-gonna-give-you-up-4",
        "https://soundcloud.com/rick-astley-official/sets/whenever-you-need-somebody",
    ])
    func servicesOutsideTheTableStay(_ string: String) {
        #expect(MusicLink.classify(string) == nil)
    }

    // MARK: Other services in the table

    @Test(arguments: [
        ("https://www.deezer.com/track/3135556", MusicLink.Service.deezer, MusicLink.Kind.song, "https://www.deezer.com/track/3135556"),
        ("https://www.deezer.com/en/track/3135556?utm_source=x", .deezer, .song, "https://www.deezer.com/track/3135556"),
        ("https://deezer.com/fr/album/302127", .deezer, .album, "https://www.deezer.com/album/302127"),
        ("https://tidal.com/browse/track/77646169", .tidal, .song, "https://tidal.com/browse/track/77646169"),
        ("https://listen.tidal.com/track/77646169", .tidal, .song, "https://tidal.com/browse/track/77646169"),
        ("https://tidal.com/album/77646168?u", .tidal, .album, "https://tidal.com/browse/album/77646168"),
        ("https://artist.bandcamp.com/track/a-song", .bandcamp, .song, "https://artist.bandcamp.com/track/a-song"),
        ("https://the-band.bandcamp.com/album/an-album-2?from=x", .bandcamp, .album, "https://the-band.bandcamp.com/album/an-album-2"),
    ])
    func otherServices(_ input: String, _ service: MusicLink.Service, _ kind: MusicLink.Kind, _ canonical: String) throws {
        let link = try #require(MusicLink.classify(input))
        #expect(link.service == service)
        #expect(link.kind == kind)
        #expect(link.canonicalURL.absoluteString == canonical)
    }

    @Test(arguments: [
        "https://www.deezer.com/playlist/908622995",
        "https://www.deezer.com/artist/27",
        "https://www.deezer.com/track/abc",
        "https://tidal.com/browse/playlist/0b5df380-47d3-48fe-ae66-8f0dba90b1ee",
        "https://tidal.com/browse/artist/3346",
        "https://artist.bandcamp.com/",
        "https://artist.bandcamp.com/music",
        "https://bandcamp.com/discover",
        "https://www.bandcamp.com/track/a-song",
    ])
    func otherServiceTypesStay(_ string: String) {
        #expect(MusicLink.classify(string) == nil)
    }

    // MARK: Target

    @Test func songLinkTargetAppendsTheCanonicalURL() throws {
        let link = try #require(MusicLink.classify("https://open.spotify.com/intl-de/track/\(Self.track)?si=abc&utm_source=x"))
        #expect(link.songLinkURL.absoluteString == "https://song.link/https://open.spotify.com/track/\(Self.track)")
    }

    @Test func songLinkTargetOfAnAlbum() throws {
        let link = try #require(MusicLink.classify("spotify:album:\(Self.album)"))
        #expect(link.songLinkURL.absoluteString == "https://song.link/https://open.spotify.com/album/\(Self.album)")
    }

    @Test func songLinkTargetOfAnotherService() throws {
        let link = try #require(MusicLink.classify("https://www.deezer.com/en/track/3135556"))
        #expect(link.songLinkURL.absoluteString == "https://song.link/https://www.deezer.com/track/3135556")
        #expect(link.songLinkURL.host == "song.link")
    }

    // MARK: HTML body

    @Test func originalLinksAreTheMarkedHrefsAsWritten() {
        let spotify = "https://open.spotify.com/track/\(Self.track)?si=abc&amp;nd=1"
        let html = #"<p>listen <a href="\#(spotify)">this</a>, "#
            + #"not <a href="https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M">that</a>, "#
            + #"and <A class="x" HREF='https://www.deezer.com/album/302127'>this one</A></p>"#
        #expect(MusicLink.originalLinks(inHTML: html) == [
            "https://open.spotify.com/track/\(Self.track)?si=abc&nd=1",
            "https://www.deezer.com/album/302127",
        ])
    }

    @Test func aBodyWithNoMusicLinkHasNone() {
        #expect(MusicLink.originalLinks(inHTML: "<p>no links</p>").isEmpty)
        #expect(MusicLink.originalLinks(inHTML: #"<a href="https://spotify.link/AbC">short</a>"#).isEmpty)
        #expect(MusicLink.originalLinks(inHTML: "https://open.spotify.com/track/\(Self.track)").isEmpty)
    }

    // MARK: Setting

    @Test func theSwitchIsOnByDefault() throws {
        let suite = "MusicLinkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(MusicLinkPreferences.isOn(in: defaults))
        defaults.set(false, forKey: MusicLinkPreferences.storageKey)
        #expect(!MusicLinkPreferences.isOn(in: defaults))
    }
}

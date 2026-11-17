import Foundation

/// A link to one song or one album on a music service that is not Apple
/// Music (MATRIX-178).
///
/// The timeline keeps the link text and sends a click to
/// `https://song.link/<canonical URL>`, where Apple Music is one click away.
/// The app makes no request: `songLinkURL` is built here from the URL alone.
/// The public Songlink API retired on 2026-07-31
/// (`docs/research/music-link-rewrite.md`, A1).
///
/// The rules are in `classify(_:)`. A rule exists only where the URL itself
/// says song or album. If in doubt, there is no rule and the link stays as
/// it is.
public struct MusicLink: Equatable, Sendable {
    /// The services with a rule.
    public enum Service: String, Equatable, Sendable, CaseIterable {
        case spotify
        case deezer
        case tidal
        case bandcamp
    }

    /// What the link points to.
    public enum Kind: String, Equatable, Sendable {
        case song
        case album
    }

    public let service: Service
    public let kind: Kind
    /// The link in the service's canonical form: type and ID only. All query
    /// items of the posted URL (Spotify's `si` identifies the share) and any
    /// locale prefix are gone.
    public let canonicalURL: URL

    /// The click target: the canonical URL appended to `https://song.link/`,
    /// not encoded. This is the form Linktree gives for personal use, and
    /// the form that resolved for a Spotify track on 2026-11-17 (research
    /// note A3).
    public var songLinkURL: URL {
        // Both parts are ASCII URLs, so the string always parses.
        URL(string: Self.songLinkPrefix + canonicalURL.absoluteString) ?? canonicalURL
    }

    static let songLinkPrefix = "https://song.link/"

    init?(service: Service, kind: Kind, canonical: String) {
        guard let url = URL(string: canonical) else { return nil }
        self.service = service
        self.kind = kind
        canonicalURL = url
    }

    // MARK: - Classifier

    /// The music link for `string`, or nil when the link must stay as it is.
    public static func classify(_ string: String) -> MusicLink? {
        URL(string: string.trimmingCharacters(in: .whitespaces)).flatMap(classify)
    }

    /// The music link for `url`, or nil when the link must stay as it is:
    /// a playlist, an artist, a podcast, an episode, a user, a short link
    /// (`spotify.link`, `spotify.app.link`, `deezer.page.link`: the type is
    /// not known without a request), Apple Music, and every other URL.
    public static func classify(_ url: URL) -> MusicLink? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "spotify" {
            return spotifyURI(url.absoluteString)
        }
        guard scheme == "https" || scheme == "http", let host = url.host?.lowercased() else { return nil }
        let path = url.path.split(separator: "/").map(String.init)

        switch host {
        case "open.spotify.com":
            return spotify(path)
        case "www.deezer.com", "deezer.com":
            return deezer(path)
        case "tidal.com", "www.tidal.com", "listen.tidal.com":
            return tidal(path)
        default:
            if host.hasSuffix(".bandcamp.com") {
                return bandcamp(host: host, path: path)
            }
            return nil
        }
    }

    /// `kind` for a path segment that names a song or an album.
    private static func kind(_ segment: String, song: String, album: String) -> Kind? {
        switch segment {
        case song: .song
        case album: .album
        default: nil
        }
    }

    /// `open.spotify.com/[intl-<locale>/](track|album)/<22 base62>`.
    private static func spotify(_ path: [String]) -> MusicLink? {
        var path = path[...]
        if let first = path.first, first.hasPrefix("intl-") {
            path = path.dropFirst()
        }
        guard path.count == 2, let kind = kind(path[path.startIndex], song: "track", album: "album") else { return nil }
        return spotify(kind: kind, id: path[path.startIndex + 1])
    }

    /// `spotify:track:<id>` and `spotify:album:<id>`, when such a URI is the
    /// target of a link in a body. Bare URIs in text are not links.
    private static func spotifyURI(_ uri: String) -> MusicLink? {
        let parts = uri.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let kind = kind(parts[1], song: "track", album: "album") else { return nil }
        return spotify(kind: kind, id: parts[2])
    }

    private static func spotify(kind: Kind, id: String) -> MusicLink? {
        guard id.count == 22, id.allSatisfy(\.isBase62) else { return nil }
        let type = kind == .song ? "track" : "album"
        return MusicLink(service: .spotify, kind: kind, canonical: "https://open.spotify.com/\(type)/\(id)")
    }

    /// `www.deezer.com/[<locale>/](track|album)/<digits>`.
    private static func deezer(_ path: [String]) -> MusicLink? {
        var path = path[...]
        if path.count == 3, let first = path.first, first.count <= 5, first.allSatisfy({ $0.isLetter || $0 == "-" }) {
            path = path.dropFirst()
        }
        guard path.count == 2, let kind = kind(path[path.startIndex], song: "track", album: "album") else { return nil }
        let id = path[path.startIndex + 1]
        guard !id.isEmpty, id.allSatisfy(\.isASCIIDigit) else { return nil }
        return MusicLink(service: .deezer, kind: kind, canonical: "https://www.deezer.com/\(kind == .song ? "track" : "album")/\(id)")
    }

    /// `tidal.com/[browse/](track|album)/<digits>` and the same on
    /// `listen.tidal.com`.
    private static func tidal(_ path: [String]) -> MusicLink? {
        var path = path[...]
        if path.first == "browse" {
            path = path.dropFirst()
        }
        guard path.count == 2, let kind = kind(path[path.startIndex], song: "track", album: "album") else { return nil }
        let id = path[path.startIndex + 1]
        guard !id.isEmpty, id.allSatisfy(\.isASCIIDigit) else { return nil }
        return MusicLink(service: .tidal, kind: kind, canonical: "https://tidal.com/browse/\(kind == .song ? "track" : "album")/\(id)")
    }

    /// `<artist>.bandcamp.com/(track|album)/<slug>`.
    private static func bandcamp(host: String, path: [String]) -> MusicLink? {
        let artist = host.dropLast(".bandcamp.com".count)
        guard !artist.isEmpty, artist.allSatisfy(\.isSlug), artist != "www",
              path.count == 2, let kind = kind(path[0], song: "track", album: "album")
        else { return nil }
        let slug = path[1]
        guard !slug.isEmpty, slug.allSatisfy(\.isSlug) else { return nil }
        return MusicLink(service: .bandcamp, kind: kind, canonical: "https://\(host)/\(path[0])/\(slug)")
    }

    // MARK: - HTML body

    /// The `href` targets of the `<a>` tags in an HTML body that `classify`
    /// accepts, in document order, as the sender wrote them. The message
    /// menu reads these for "Open Original Link" and "Copy Original Link".
    public static func originalLinks(inHTML html: String) -> [String] {
        guard let hrefPattern, html.range(of: "href", options: .caseInsensitive) != nil else { return [] }
        let text = html as NSString
        return hrefPattern.matches(in: html, range: NSRange(location: 0, length: text.length)).compactMap { match in
            let range = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            guard range.location != NSNotFound else { return nil }
            let href = decodingEntities(text.substring(with: range))
            return classify(href) == nil ? nil : href
        }
    }

    /// `href="…"` or `href='…'` inside an `<a>` tag. The pattern is a
    /// literal, so it always compiles; a test checks it.
    private static let hrefPattern = try? NSRegularExpression(
        pattern: #"<a\s[^>]*?href\s*=\s*(?:"([^"]*)"|'([^']*)')"#,
        options: [.caseInsensitive]
    )

    /// The entities an attribute value can hold in a URL.
    private static func decodingEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// The switch for the music link marker (MATRIX-178, Settings >
/// Appearance).
///
/// Stored with `@AppStorage` under `storageKey`. The key is a persisted user
/// setting: do not rename it. A key that was never written reads as the
/// default, on.
public enum MusicLinkPreferences {
    /// `UserDefaults` key of the switch.
    public static let storageKey = "opensMusicLinksThroughSongLink"
    /// The value when the user never changed it.
    public static let defaultValue = true

    /// The stored value, or the default.
    public static func isOn(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? defaultValue
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }

    var isBase62: Bool {
        isASCII && (isLetter || isNumber)
    }

    var isSlug: Bool {
        isASCII && (isLowercase || isNumber || self == "-")
    }
}

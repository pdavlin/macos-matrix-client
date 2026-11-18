import Foundation

/// The title of a Spotify song or album link (MATRIX-191): the artist and
/// the name of the song or the album, read from the homeserver's URL preview
/// of the link (`MusicLinkPreviewReader`).
///
/// The timeline shows `text` in place of the link's URL.
public struct MusicLinkTitle: Codable, Equatable, Sendable {
    /// The artist, as the first part of `og:description` gives it. Several
    /// artists show as `A, B`.
    public let artist: String
    /// The name of the song or the album.
    public let name: String

    public init(artist: String, name: String) {
        self.artist = artist
        self.name = name
    }

    /// `Artist · Name`, with U+00B7 and a space on each side.
    public var text: String {
        "\(artist)\(Self.separator)\(name)"
    }

    /// The separator of `text`, and of the parts of Spotify's
    /// `og:description`.
    public static let separator = " \u{00B7} "

    /// The title in the preview JSON of a link of `kind`, or nil if the
    /// preview is not a Spotify song or album page as expected.
    ///
    /// Rules (for the answers of 2026-11-18, see the tests):
    /// - `og:type` must be `music.song` for a song and `music.album` for an
    ///   album. Any other page (an error page, a page of another type) has no
    ///   title.
    /// - The artist is the first ` · ` part of `og:description`.
    /// - A song's name is `og:title`.
    /// - An album's name comes from `og:title` by the pattern
    ///   `Listen to <name> - Album by <artist> | Spotify` (also `Single` and
    ///   `EP` in place of `Album`). An `og:title` without ` | Spotify` is the
    ///   name as it is. Any other `og:title` has no name.
    /// - An empty artist or name gives no title.
    public static func parse(_ data: Data, kind: MusicLink.Kind) -> MusicLinkTitle? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["og:type"] as? String,
              let title = object["og:title"] as? String,
              let description = object["og:description"] as? String
        else { return nil }
        let expectedType = kind == .song ? "music.song" : "music.album"
        guard type == expectedType else { return nil }

        let firstPart = description.components(separatedBy: separator).first ?? ""
        let artist = firstPart.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = switch kind {
        case .song: title.trimmingCharacters(in: .whitespacesAndNewlines)
        case .album: albumName(fromTitle: title, artist: artist)
        }
        guard !artist.isEmpty, let name, !name.isEmpty else { return nil }
        return MusicLinkTitle(artist: artist, name: name)
    }

    private static let spotifySuffix = " | Spotify"

    /// The album name in an album page's `og:title`, or nil.
    private static func albumName(fromTitle title: String, artist: String) -> String? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "Listen to "
        guard title.hasPrefix(prefix), title.hasSuffix(spotifySuffix) else {
            return title.contains(spotifySuffix) ? nil : title
        }
        let middle = String(title.dropFirst(prefix.count).dropLast(spotifySuffix.count))
        // The artist is known, so try the exact end first: a name can hold
        // " - Album by " itself.
        for type in ["Album", "Single", "EP"] {
            let ending = " - \(type) by \(artist)"
            if !artist.isEmpty, middle.hasSuffix(ending) {
                return String(middle.dropLast(ending.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        for type in ["Album", "Single", "EP"] {
            if let range = middle.range(of: " - \(type) by ", options: .backwards) {
                return String(middle[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

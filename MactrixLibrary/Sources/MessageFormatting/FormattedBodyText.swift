import Models
import SwiftUI
import Tokens
import UI

/// A message's HTML body, with its custom emoticons (MATRIX-153).
///
/// The body draws at once from what the image loader's cache holds. An
/// emoticon the cache does not hold draws as its alt text in the same square.
/// The task then loads each missing image through the loader, and each
/// arrival draws the body again in place. The squares do not change size, so
/// the height is the same before and after.
///
/// A jumbo body (MATRIX-162) draws at `TypographyToken.jumboEmojiSize` in
/// place of the base size. Each emoticon square takes its side from the font
/// around it, so the image and its alt text grow with the Unicode emoji.
///
/// The same task reports the body's emoticons through `onEmoticons`
/// (MATRIX-161), from the one parse that finds the images to load. The app
/// records them as the learned emoji of the chat's workspace.
///
/// With `marksMusicLinks`, a music link draws with its marker and opens on
/// song.link (MATRIX-178). The timeline's height measure builds this same
/// view with the same switch, so the measured and the drawn string agree.
/// Its gradient bar (MATRIX-187) draws behind the text, and its click areas
/// lie over the text. Neither adds height.
///
/// On macOS, a Spotify link that shows its URL shows its title when
/// `musicLinkTitles` holds one (MATRIX-191). The body reads the store as it
/// parses, so a title that arrives draws the body again. When the body shows,
/// a task asks the store to load the titles of its links.
public struct FormattedBodyText: View {
    let html: String
    let baseFontSize: CGFloat
    let isJumbo: Bool
    let imageLoader: (any ImageLoader)?
    let onEmoticons: (@MainActor ([BodyEmoticon]) -> Void)?
    let marksMusicLinks: Bool
    let musicLinkTitles: MusicLinkTitleStore?

    /// Counts the emoticon images that arrived. `body` reads it, so each
    /// arrival parses the body again against the cache.
    @State private var arrivals = 0

    /// - Parameters:
    ///   - html: The formatted body.
    ///   - baseFontSize: The body text size.
    ///   - isJumbo: True for a body that `Models.JumboEmoji.kind` finds to be
    ///     `.formatted`. The body then draws at the jumbo emoji size.
    ///   - imageLoader: Loads the emoticon images. Nil draws the alt texts.
    ///   - onEmoticons: Takes the body's emoticons when the body shows, and
    ///     again when the body changes. Not called for a body with none.
    ///   - marksMusicLinks: The Settings switch of the music link marker
    ///     (`Models.MusicLinkPreferences`). Off by default, so a caller that
    ///     does not read the setting draws links as before.
    ///   - musicLinkTitles: The titles of the Spotify links (MATRIX-191). The
    ///     app's store by default. Nil shows every link's URL.
    public init(
        html: String,
        baseFontSize: CGFloat,
        isJumbo: Bool = false,
        imageLoader: (any ImageLoader)?,
        onEmoticons: (@MainActor ([BodyEmoticon]) -> Void)? = nil,
        marksMusicLinks: Bool = false,
        musicLinkTitles: MusicLinkTitleStore? = .shared
    ) {
        self.html = html
        self.baseFontSize = baseFontSize
        self.isJumbo = isJumbo
        self.imageLoader = imageLoader
        self.onEmoticons = onEmoticons
        self.marksMusicLinks = marksMusicLinks
        self.musicLinkTitles = musicLinkTitles
    }

    private var fontSize: CGFloat {
        isJumbo ? TypographyToken.jumboEmojiSize : baseFontSize
    }

    /// Takes the arrival count so that `body` depends on it. The cache, not
    /// the count, decides what each emoticon draws.
    private func attributedBody(arrivals _: Int) -> NSAttributedString {
        parseFormattedBody(
            html,
            baseFontSize: fontSize,
            imageLoader: imageLoader,
            marksMusicLinks: marksMusicLinks,
            musicLinkTitles: musicLinkTitles
        )
    }

    /// Asks the store for the titles of the body's Spotify links. The store
    /// reads only the links it has no answer for, and one read per link.
    private func loadMusicLinkTitles() {
        #if canImport(AppKit)
            guard marksMusicLinks, let musicLinkTitles else { return }
            for link in musicLinkTitleCandidates(inFormattedBody: html, baseFontSize: fontSize) {
                musicLinkTitles.load(link)
            }
        #endif
    }

    public var body: some View {
        let text = AttributedTextView(attributedString: attributedBody(arrivals: arrivals))
        text
            .musicLinkBar(for: text.attributedString)
            .task(id: marksMusicLinks ? html : "") { loadMusicLinkTitles() }
            .task(id: html) {
                let found: [BodyEmoticon] = emoticons(inFormattedBody: html)
                guard !found.isEmpty else { return }
                onEmoticons?(found)
                guard let imageLoader else { return }
                for source in found.map(\.source) where imageLoader.cachedImage(matrixUrl: source) == nil {
                    // `size: nil` on purpose: the loader caches a sized load under
                    // another key, which `cachedImage(matrixUrl:)` does not find.
                    // A failed load leaves the alt text in place.
                    if await (try? imageLoader.loadImage(matrixUrl: source, size: nil)) != nil {
                        arrivals += 1
                    }
                }
            }
    }
}

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
public struct FormattedBodyText: View {
    let html: String
    let baseFontSize: CGFloat
    let isJumbo: Bool
    let imageLoader: (any ImageLoader)?
    let onEmoticons: (@MainActor ([BodyEmoticon]) -> Void)?
    let marksMusicLinks: Bool

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
    public init(
        html: String,
        baseFontSize: CGFloat,
        isJumbo: Bool = false,
        imageLoader: (any ImageLoader)?,
        onEmoticons: (@MainActor ([BodyEmoticon]) -> Void)? = nil,
        marksMusicLinks: Bool = false
    ) {
        self.html = html
        self.baseFontSize = baseFontSize
        self.isJumbo = isJumbo
        self.imageLoader = imageLoader
        self.onEmoticons = onEmoticons
        self.marksMusicLinks = marksMusicLinks
    }

    /// Takes the arrival count so that `body` depends on it. The cache, not
    /// the count, decides what each emoticon draws.
    private func attributedBody(arrivals _: Int) -> NSAttributedString {
        parseFormattedBody(
            html,
            baseFontSize: isJumbo ? TypographyToken.jumboEmojiSize : baseFontSize,
            imageLoader: imageLoader,
            marksMusicLinks: marksMusicLinks
        )
    }

    public var body: some View {
        let text = AttributedTextView(attributedString: attributedBody(arrivals: arrivals))
        text
            .musicLinkBar(for: text.attributedString)
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

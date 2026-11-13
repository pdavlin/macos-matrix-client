import SwiftUI
import UI

/// A message's HTML body, with its custom emoticons (MATRIX-153).
///
/// The body draws at once from what the image loader's cache holds. An
/// emoticon the cache does not hold draws as its alt text in the same square.
/// The task then loads each missing image through the loader, and each
/// arrival draws the body again in place. The squares do not change size, so
/// the height is the same before and after.
public struct FormattedBodyText: View {
    let html: String
    let baseFontSize: CGFloat
    let imageLoader: (any ImageLoader)?

    /// Counts the emoticon images that arrived. `body` reads it, so each
    /// arrival parses the body again against the cache.
    @State private var arrivals = 0

    public init(html: String, baseFontSize: CGFloat, imageLoader: (any ImageLoader)?) {
        self.html = html
        self.baseFontSize = baseFontSize
        self.imageLoader = imageLoader
    }

    /// Takes the arrival count so that `body` depends on it. The cache, not
    /// the count, decides what each emoticon draws.
    private func attributedBody(arrivals _: Int) -> NSAttributedString {
        parseFormattedBody(html, baseFontSize: baseFontSize, imageLoader: imageLoader)
    }

    public var body: some View {
        AttributedTextView(attributedString: attributedBody(arrivals: arrivals))
            .task(id: html) {
                guard let imageLoader else { return }
                for source in emoticonSources(inFormattedBody: html) where imageLoader.cachedImage(matrixUrl: source) == nil {
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

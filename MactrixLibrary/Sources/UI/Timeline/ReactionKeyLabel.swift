import Models
import OSLog
import SwiftUI
import Tokens

public extension EnvironmentValues {
    /// Loads the images a timeline surface draws outside a message row
    /// (MATRIX-154): the custom emoji of a quick reaction in the hover bar.
    /// Nil draws the generic glyph. The rows themselves get their loader as
    /// a parameter.
    @Entry var timelineImageLoader: (any ImageLoader)?
}

/// Draws one reaction key (MATRIX-154): an `mxc://` key as its image, any
/// other key as text. `ReactionKeyKind` decides which.
///
/// Usage:
/// ```swift
/// ReactionKeyLabel(key: reaction.key, imageLoader: imageLoader)
/// ```
struct ReactionKeyLabel: View {
    let key: String
    let imageLoader: ImageLoader?

    var body: some View {
        switch ReactionKeyKind(key: key) {
        case let .image(mxcUrl):
            ReactionKeyImage(mxcUrl: mxcUrl, imageLoader: imageLoader)
        case .unicode, .shortcode:
            Text(key)
        }
    }
}

/// A custom emoji image in the box of one emoji glyph.
///
/// A hidden emoji in the current font sets the size, so an image chip has
/// the size of a Unicode emoji chip in every font size, and the size is the
/// same while the image loads, after it loads, and after a failed load. The
/// timeline rows are pre-measured (MATRIX-49/50/63), so the size must not
/// depend on the load.
///
/// The image comes from the `ImageLoader` the avatars use, with its cache.
/// While the load runs the box shows a neutral square. A failed load, or no
/// loader, shows a generic glyph.
struct ReactionKeyImage: View {
    let mxcUrl: String
    let imageLoader: ImageLoader?

    private enum Phase {
        case loading
        case loaded(Image)
        case failed
    }

    @State private var phase: Phase

    init(mxcUrl: String, imageLoader: ImageLoader?) {
        self.mxcUrl = mxcUrl
        self.imageLoader = imageLoader
        if let cached = imageLoader?.cachedImage(matrixUrl: mxcUrl) {
            _phase = State(initialValue: .loaded(cached))
        } else {
            _phase = State(initialValue: imageLoader == nil ? .failed : .loading)
        }
    }

    var body: some View {
        Text(verbatim: ReactionToken.imageSizeReference)
            .hidden()
            .overlay { content }
            .transaction { $0.animation = nil }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(ReactionKeyKind.customEmojiName))
            .task(id: mxcUrl, priority: .utility) { await load() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case let .loaded(image):
            image
                .resizable()
                .scaledToFit()
        case .loading:
            RoundedRectangle(cornerRadius: ReactionToken.imagePlaceholderCornerRadius)
                .fill(Color.gray.opacity(ReactionToken.imagePlaceholderOpacity))
                .aspectRatio(1, contentMode: .fit)
        case .failed:
            Image(systemName: ReactionToken.imageFailedSystemImage)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        guard let imageLoader else {
            phase = .failed
            return
        }
        // The cache first: a reused cell can hold the state of another key.
        if let cached = imageLoader.cachedImage(matrixUrl: mxcUrl) {
            phase = .loaded(cached)
            return
        }
        phase = .loading
        do {
            if let image = try await imageLoader.loadImage(matrixUrl: mxcUrl, size: nil) {
                phase = .loaded(image)
            } else {
                phase = .failed
            }
        } catch is CancellationError {
            // The view went away or the key changed. The next task decides.
        } catch {
            Logger.viewCycle.error("failed to load reaction image: \(error)")
            phase = .failed
        }
    }
}

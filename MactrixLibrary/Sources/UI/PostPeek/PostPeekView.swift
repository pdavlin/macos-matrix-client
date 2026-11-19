#if os(macOS)
    import AVKit
    import Models
    import SwiftUI
    import Tokens

    /// The content of the post peek popover (MATRIX-201): one X or Bluesky
    /// post, read and left without a browser.
    ///
    /// The layout follows post-peek (https://github.com/tsvb/post-peek, MIT):
    /// the author, "Replying to", the text with its links, photos or video,
    /// the link card, the quoted post, then the date and "Open on X" or
    /// "Open on Bluesky". A quoted post and the post replied to open in the
    /// same popover, with Back. A failed read shows why, with "Open in
    /// Browser". Bluesky media labeled adult or graphic stays behind a click.
    ///
    /// Links open through the environment's `openURL`. The app's popover
    /// sends an X or Bluesky post link back into this view, and any other
    /// link to the browser. "Open on X", "Open on Bluesky" and "Open in
    /// Browser" open through `postPeekBrowserAction`, so they reach the
    /// browser also for a post link.
    public struct PostPeekView: View {
        let model: PostPeekModel

        public init(model: PostPeekModel) {
            self.model = model
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if model.canGoBack {
                    Button {
                        model.back()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, PostPeekToken.padding)
                    .padding(.top, PostPeekToken.padding)
                }
                ScrollView {
                    PostPeekPage(page: model.page)
                        .padding(PostPeekToken.padding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: PostPeekToken.maxHeight)
            }
            .frame(width: PostPeekToken.width)
            .environment(model)
            .task { model.start() }
        }
    }

    /// The loading, failed or loaded state of one page.
    private struct PostPeekPage: View {
        let page: PostPeekModel.Page
        @Environment(\.openURL) private var openURL
        @Environment(\.postPeekBrowserAction) private var browser

        var body: some View {
            switch page.state {
            case .loading:
                VStack(spacing: PostPeekToken.spacing) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Peeking…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: PostPeekToken.statusMinHeight)
            case let .failed(failure):
                VStack(alignment: .leading, spacing: PostPeekToken.spacing) {
                    Text(failure.message(site: page.link.site))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(failure.isWithheld ? "Open on \(page.link.site.name)" : "Open in Browser") {
                        (browser ?? openURL)(page.fallbackURL)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: PostPeekToken.statusMinHeight, alignment: .leading)
            case let .loaded(post):
                PeekPostView(post: post)
                    .id(page.id)
            }
        }
    }

    /// A loaded post.
    struct PeekPostView: View {
        let post: PeekPost
        @Environment(PostPeekModel.self) private var model
        @Environment(\.openURL) private var openURL
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone
        @Environment(\.postPeekBrowserAction) private var browser
        @State private var showsContent = false

        var body: some View {
            VStack(alignment: .leading, spacing: PostPeekToken.spacing) {
                PeekAuthorHeader(author: post.author, avatarSize: PostPeekToken.avatarSize, fontSize: PostPeekToken.textSize)
                if let reply = post.replyTo {
                    PeekReplyLine(reply: reply)
                }
                if post.hasContentWarning, !showsContent {
                    PeekRevealButton(title: "Content warning") { showsContent = true }
                } else {
                    PeekBody(post: post, nested: false)
                }
                footer
            }
        }

        private var footer: some View {
            HStack(alignment: .firstTextBaseline) {
                if let date = post.date {
                    Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone)))
                        .font(.system(size: PostPeekToken.secondaryTextSize))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: PostPeekToken.spacing)
                Button("Open on \(post.link.site.name)") {
                    (browser ?? openURL)(post.url)
                }
            }
        }
    }

    /// The text, media, card and quote of a post. A quoted post (`nested`)
    /// shows only its text and media.
    private struct PeekBody: View {
        let post: PeekPost
        let nested: Bool
        @State private var showsMedia = false

        var body: some View {
            VStack(alignment: .leading, spacing: PostPeekToken.spacing) {
                if !post.text.isEmpty {
                    Text(Self.attributed(post.text))
                        .font(.system(size: nested ? PostPeekToken.secondaryTextSize : PostPeekToken.textSize))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if hasMedia {
                    if let warning = post.mediaWarning, !showsMedia {
                        PeekRevealButton(title: "Media labeled “\(warning)”") { showsMedia = true }
                    } else {
                        media
                    }
                }
                if !nested, let quote = post.quote {
                    PeekQuoteView(quote: quote)
                }
            }
        }

        private var hasMedia: Bool {
            !post.photos.isEmpty || !post.videos.isEmpty || (!nested && post.card != nil)
        }

        @ViewBuilder
        private var media: some View {
            ForEach(Array(post.videos.enumerated()), id: \.offset) { _, video in
                PeekVideoView(video: video)
            }
            if !post.photos.isEmpty {
                PeekPhotoGrid(photos: post.photos)
            }
            if !nested, let card = post.card {
                PeekCardView(card: card)
            }
        }

        static func attributed(_ runs: [PeekTextRun]) -> AttributedString {
            var text = AttributedString()
            for run in runs {
                var part = AttributedString(run.text)
                if let link = run.link {
                    part.link = link
                }
                text += part
            }
            return text
        }
    }

    private struct PeekAuthorHeader: View {
        let author: PeekAuthor
        let avatarSize: CGFloat
        let fontSize: CGFloat
        @Environment(\.openURL) private var openURL

        var body: some View {
            Button {
                if let profile = author.profileURL {
                    openURL(profile)
                }
            } label: {
                HStack(spacing: PostPeekToken.spacing * 0.8) {
                    PeekImage(url: author.avatarURL)
                        .frame(width: avatarSize, height: avatarSize)
                        .clipShape(Circle())
                    if avatarSize >= PostPeekToken.avatarSize {
                        VStack(alignment: .leading, spacing: 1) {
                            name
                            handle
                        }
                    } else {
                        HStack(spacing: 4) {
                            name
                            handle
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(author.profileURL == nil)
            .accessibilityLabel("\(author.name), @\(author.handle)")
        }

        private var name: some View {
            HStack(spacing: 3) {
                Text(author.name)
                    .font(.system(size: fontSize, weight: .semibold))
                    .lineLimit(1)
                if author.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: fontSize * 0.85))
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Verified")
                }
            }
        }

        private var handle: some View {
            Text("@\(author.handle)")
                .font(.system(size: PostPeekToken.secondaryTextSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private struct PeekReplyLine: View {
        let reply: PeekReplyContext
        @Environment(PostPeekModel.self) private var model

        var body: some View {
            HStack(spacing: 3) {
                Text("Replying to")
                    .foregroundStyle(.secondary)
                if let link = reply.link {
                    Button(reply.label) { model.open(link) }
                        .buttonStyle(.link)
                } else {
                    Text(reply.label)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: PostPeekToken.secondaryTextSize))
        }
    }

    /// A gate in front of labeled content: a button that shows it.
    private struct PeekRevealButton: View {
        let title: String
        let reveal: () -> Void

        var body: some View {
            Button(action: reveal) {
                Label("\(title). Show", systemImage: "eye.slash")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
    }

    /// An image read through the post peek store, on a plain fill until it
    /// arrives.
    private struct PeekImage: View {
        let url: URL?
        @Environment(PostPeekModel.self) private var model

        var body: some View {
            Rectangle()
                .fill(Color.primary.opacity(PostPeekToken.placeholderOpacity))
                .overlay {
                    if let url, let image = model.store.image(for: url) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipped()
                .task(id: url) {
                    if let url {
                        await model.store.loadImage(url)
                    }
                }
        }
    }

    private struct PeekPhotoGrid: View {
        let photos: [PeekPhoto]

        var body: some View {
            Group {
                if photos.count == 1, let photo = photos.first {
                    PeekImage(url: photo.url)
                        .aspectRatio(PeekMediaRatio.single(photo.aspectRatio), contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .help(photo.alt)
                        .accessibilityLabel(photo.alt)
                } else {
                    let rows = stride(from: 0, to: photos.count, by: 2).map { Array(photos[$0 ..< min($0 + 2, photos.count)]) }
                    VStack(spacing: PostPeekToken.mediaSpacing) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: PostPeekToken.mediaSpacing) {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, photo in
                                    PeekImage(url: photo.url)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: PostPeekToken.gridCellHeight)
                                        .help(photo.alt)
                                        .accessibilityLabel(photo.alt)
                                }
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: PostPeekToken.cornerRadius))
        }
    }

    enum PeekMediaRatio {
        /// The width over height a single photo or video draws at: its own,
        /// but never taller than `PostPeekToken.singleMediaMaxHeight` at the
        /// popover's width.
        static func single(_ ratio: Double?) -> CGFloat {
            let widest = (PostPeekToken.width - 2 * PostPeekToken.padding) / PostPeekToken.singleMediaMaxHeight
            return max(CGFloat(ratio ?? 16.0 / 9.0), widest)
        }
    }

    /// A video: its poster with a play glyph until a click, then AVPlayer. A
    /// GIF plays at once, muted, in a loop. Nothing loads from the video
    /// host before that.
    private struct PeekVideoView: View {
        let video: PeekVideo
        @State private var player: AVPlayer?
        @State private var looper: AVPlayerLooper?

        var body: some View {
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    Button(action: play) {
                        PeekImage(url: video.posterURL)
                            .overlay {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: PostPeekToken.playGlyphSize))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.5))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play video")
                }
            }
            .aspectRatio(PeekMediaRatio.single(video.aspectRatio), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: PostPeekToken.cornerRadius))
            .onAppear {
                if video.isGIF {
                    play()
                }
            }
            .onDisappear {
                player?.pause()
            }
        }

        private func play() {
            guard player == nil else { return }
            // No cookies go with the video's requests.
            let asset = AVURLAsset(url: video.url, options: [AVURLAssetHTTPCookiesKey: [HTTPCookie]()])
            let item = AVPlayerItem(asset: asset)
            if video.isGIF {
                let queue = AVQueuePlayer()
                queue.isMuted = true
                looper = AVPlayerLooper(player: queue, templateItem: item)
                player = queue
            } else {
                player = AVPlayer(playerItem: item)
            }
            player?.play()
        }
    }

    private struct PeekCardView: View {
        let card: PeekCard
        @Environment(\.openURL) private var openURL

        var body: some View {
            Button {
                openURL(card.url)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    if let image = card.imageURL {
                        PeekImage(url: image)
                            .frame(maxWidth: .infinity)
                            .frame(height: PostPeekToken.cardImageHeight)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.domain)
                            .font(.system(size: PostPeekToken.secondaryTextSize))
                            .foregroundStyle(.secondary)
                        Text(card.title)
                            .font(.system(size: PostPeekToken.textSize, weight: .semibold))
                            .lineLimit(2)
                        if let description = card.description {
                            Text(description)
                                .font(.system(size: PostPeekToken.secondaryTextSize))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .padding(PostPeekToken.innerPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .peekBorder()
            }
            .buttonStyle(.plain)
            .help(card.url.absoluteString)
        }
    }

    /// A quoted post. A click opens it in the popover.
    private struct PeekQuoteView: View {
        let quote: PeekQuote
        @Environment(PostPeekModel.self) private var model

        var body: some View {
            switch quote {
            case .unavailable:
                Text("The quoted post is unavailable.")
                    .font(.system(size: PostPeekToken.secondaryTextSize))
                    .foregroundStyle(.secondary)
                    .padding(PostPeekToken.innerPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .peekBorder()
            case let .post(post):
                VStack(alignment: .leading, spacing: PostPeekToken.spacing * 0.6) {
                    PeekAuthorHeader(
                        author: post.author,
                        avatarSize: PostPeekToken.quoteAvatarSize,
                        fontSize: PostPeekToken.secondaryTextSize
                    )
                    .allowsHitTesting(false)
                    if post.hasContentWarning {
                        Text("Content warning")
                            .font(.system(size: PostPeekToken.secondaryTextSize))
                            .foregroundStyle(.secondary)
                    } else {
                        PeekBody(post: post, nested: true)
                    }
                }
                .padding(PostPeekToken.innerPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .peekBorder()
                .onTapGesture { model.open(post.link) }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.open(post.link) }
            }
        }
    }

    public extension EnvironmentValues {
        /// Opens a URL in the browser, for the popover's Open buttons. Nil
        /// uses `openURL`.
        @Entry var postPeekBrowserAction: OpenURLAction?
    }

    private extension View {
        /// The rounded border of the link card and the quoted post.
        func peekBorder() -> some View {
            clipShape(RoundedRectangle(cornerRadius: PostPeekToken.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: PostPeekToken.cornerRadius)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: PostPeekToken.borderWidth)
                }
        }
    }
#endif

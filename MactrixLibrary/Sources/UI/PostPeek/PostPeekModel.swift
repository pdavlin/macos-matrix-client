#if os(macOS)
    import AppKit
    import Models
    import Observation

    /// The in-memory caches of the post peek (MATRIX-201): the posts read in
    /// the last `postLifetime`, and the images of the popover. Nothing goes
    /// to disk.
    ///
    /// The store has no network of its own. The app gives it the reads
    /// (`Models.PostPeekReader` over an ephemeral `URLSession`), so tests and
    /// previews run without a network.
    @MainActor @Observable
    public final class PostPeekStore {
        /// Reads one post.
        public typealias FetchPost = @Sendable (PostPeekLink) async throws -> PeekPost
        /// Reads the bytes of one image.
        public typealias FetchImage = @Sendable (URL) async throws -> Data

        /// How long a read post stays in the cache.
        public nonisolated static let postLifetime: TimeInterval = 5 * 60
        /// The most posts the cache holds.
        public nonisolated static let postCapacity = 50
        /// The most images the cache holds.
        public nonisolated static let imageCapacity = 150

        @ObservationIgnored private let fetchPost: FetchPost
        @ObservationIgnored private let fetchImage: FetchImage
        @ObservationIgnored private let now: @Sendable () -> Date
        @ObservationIgnored private var posts: [PostPeekLink: (post: PeekPost, expires: Date)] = [:]
        /// The loaded images. Observed, so an image that arrives draws.
        private var images: [URL: NSImage] = [:]
        @ObservationIgnored private var imageOrder: [URL] = []
        @ObservationIgnored private var imageReads: Set<URL> = []
        /// Images that failed once. They are not read again: no retry loop.
        @ObservationIgnored private var failedImages: Set<URL> = []

        public init(
            fetchPost: @escaping FetchPost,
            fetchImage: @escaping FetchImage,
            now: @escaping @Sendable () -> Date = { Date() }
        ) {
            self.fetchPost = fetchPost
            self.fetchImage = fetchImage
            self.now = now
        }

        /// The post of `link`, from the cache or read.
        public func post(_ link: PostPeekLink) async throws -> PeekPost {
            if let cached = posts[link], cached.expires > now() {
                return cached.post
            }
            let post = try await fetchPost(link)
            remember(post, for: link)
            return post
        }

        /// Puts `post` in the cache under `link`.
        public func remember(_ post: PeekPost, for link: PostPeekLink) {
            let date = now()
            posts = posts.filter { $0.value.expires > date }
            if posts.count >= Self.postCapacity, let oldest = posts.min(by: { $0.value.expires < $1.value.expires }) {
                posts[oldest.key] = nil
            }
            posts[link] = (post, date.addingTimeInterval(Self.postLifetime))
        }

        /// The loaded image at `url`, or nil.
        public func image(for url: URL) -> NSImage? {
            images[url]
        }

        /// Reads the image at `url` if the store does not hold it, is not
        /// reading it, and did not fail to read it.
        public func loadImage(_ url: URL) async {
            guard images[url] == nil, !imageReads.contains(url), !failedImages.contains(url) else { return }
            imageReads.insert(url)
            defer { imageReads.remove(url) }
            guard let data = try? await fetchImage(url), let image = NSImage(data: data) else {
                failedImages.insert(url)
                return
            }
            rememberImage(image, for: url)
        }

        /// Puts `image` in the cache under `url`.
        public func rememberImage(_ image: NSImage, for url: URL) {
            if images[url] == nil {
                imageOrder.append(url)
            }
            images[url] = image
            while imageOrder.count > Self.imageCapacity {
                images[imageOrder.removeFirst()] = nil
            }
        }
    }

    /// One post peek popover (MATRIX-201): the post of the clicked link, and
    /// the posts opened from it (a quote, the post replied to), with a way
    /// back.
    @MainActor @Observable
    public final class PostPeekModel {
        public enum State: Equatable {
            case loading
            case loaded(PeekPost)
            case failed(PostPeekFailure)
        }

        public struct Page: Identifiable, Equatable {
            public let id = UUID()
            public let link: PostPeekLink
            /// Where "Open in Browser" goes when the post fails.
            public let fallbackURL: URL
            public var state: State
        }

        /// The page on show.
        public private(set) var page: Page
        /// The pages before it, for Back.
        public private(set) var history: [Page] = []

        @ObservationIgnored public let store: PostPeekStore
        @ObservationIgnored private var load: Task<Void, Never>?

        /// - Parameters:
        ///   - link: The post to show.
        ///   - fallbackURL: The link that was clicked, for the browser.
        ///   - state: `.loading` to read the post on `start()`, or a state to
        ///     show as it is (tests and previews).
        public init(link: PostPeekLink, fallbackURL: URL, store: PostPeekStore, state: State = .loading) {
            page = Page(link: link, fallbackURL: fallbackURL, state: state)
            self.store = store
        }

        public var canGoBack: Bool {
            !history.isEmpty
        }

        /// Reads the page's post, if it is loading.
        public func start() {
            guard page.state == .loading else { return }
            let id = page.id
            let link = page.link
            load?.cancel()
            load = Task {
                let state: State
                do {
                    state = try await .loaded(store.post(link))
                } catch let failure as PostPeekFailure {
                    state = .failed(failure)
                } catch {
                    state = .failed(.network)
                }
                guard !Task.isCancelled, page.id == id else { return }
                page.state = state
            }
        }

        /// Shows the post of `link`, with Back to the page on show.
        public func open(_ link: PostPeekLink) {
            guard link != page.link else { return }
            history.append(page)
            page = Page(link: link, fallbackURL: link.webURL, state: .loading)
            start()
        }

        /// Shows the page before.
        public func back() {
            guard let previous = history.popLast() else { return }
            load?.cancel()
            page = previous
            // A page left while it loaded loads again.
            start()
        }
    }
#endif

import Foundation

/// One X or Bluesky post as the post peek popover shows it (MATRIX-201).
///
/// `PostPeekParser` makes it from the JSON of X's syndication endpoint or of
/// Bluesky's `app.bsky.feed.getPostThread`. Every link in it is an `http` or
/// `https` URL, and every media URL is an `https` URL on a media host of the
/// site (`PostPeekReader.mediaHosts`).
public struct PeekPost: Equatable, Sendable {
    /// The post itself, to peek again (a quoted post opens in the popover).
    public var link: PostPeekLink
    /// The post on the web, for "Open on X" and "Open on Bluesky".
    public var url: URL
    public var author: PeekAuthor
    public var text: [PeekTextRun]
    public var photos: [PeekPhoto]
    public var videos: [PeekVideo]
    public var card: PeekCard?
    public var quote: PeekQuote?
    /// "Replying to …", for a reply.
    public var replyTo: PeekReplyContext?
    public var date: Date?
    /// A Bluesky label (`porn`, `sexual`, `nudity`, `graphic-media`, `gore`)
    /// on the post or its author. The photos, videos and link card then stay
    /// behind a click.
    public var mediaWarning: String?
    /// True for a Bluesky post labeled `!warn`. All of the body then stays
    /// behind a click.
    public var hasContentWarning: Bool

    public init(
        link: PostPeekLink,
        url: URL,
        author: PeekAuthor,
        text: [PeekTextRun],
        photos: [PeekPhoto] = [],
        videos: [PeekVideo] = [],
        card: PeekCard? = nil,
        quote: PeekQuote? = nil,
        replyTo: PeekReplyContext? = nil,
        date: Date? = nil,
        mediaWarning: String? = nil,
        hasContentWarning: Bool = false
    ) {
        self.link = link
        self.url = url
        self.author = author
        self.text = text
        self.photos = photos
        self.videos = videos
        self.card = card
        self.quote = quote
        self.replyTo = replyTo
        self.date = date
        self.mediaWarning = mediaWarning
        self.hasContentWarning = hasContentWarning
    }

    /// The plain text of the post.
    public var plainText: String {
        text.map(\.text).joined()
    }
}

public struct PeekAuthor: Equatable, Sendable {
    public var name: String
    /// The handle without the `@`.
    public var handle: String
    public var avatarURL: URL?
    public var profileURL: URL?
    public var isVerified: Bool

    public init(name: String, handle: String, avatarURL: URL? = nil, profileURL: URL? = nil, isVerified: Bool = false) {
        self.name = name
        self.handle = handle
        self.avatarURL = avatarURL
        self.profileURL = profileURL
        self.isVerified = isVerified
    }
}

/// A run of post text, a link when `link` is set.
public struct PeekTextRun: Equatable, Sendable {
    public var text: String
    public var link: URL?

    public init(_ text: String, link: URL? = nil) {
        self.text = text
        self.link = link
    }
}

public struct PeekPhoto: Equatable, Sendable {
    public var url: URL
    public var alt: String
    /// Width over height, when the site gives it.
    public var aspectRatio: Double?

    public init(url: URL, alt: String = "", aspectRatio: Double? = nil) {
        self.url = url
        self.alt = alt
        self.aspectRatio = aspectRatio
    }
}

public struct PeekVideo: Equatable, Sendable {
    /// An MP4 file (X) or an HLS playlist (Bluesky). AVPlayer plays both.
    public var url: URL
    public var posterURL: URL?
    /// Width over height, when the site gives it.
    public var aspectRatio: Double?
    /// A GIF the site keeps as a video: it plays on its own, muted, in a loop.
    public var isGIF: Bool

    public init(url: URL, posterURL: URL? = nil, aspectRatio: Double? = nil, isGIF: Bool = false) {
        self.url = url
        self.posterURL = posterURL
        self.aspectRatio = aspectRatio
        self.isGIF = isGIF
    }
}

/// The preview card of a link in the post.
public struct PeekCard: Equatable, Sendable {
    public var url: URL
    public var title: String
    public var description: String?
    public var imageURL: URL?
    /// The host the card names, for example `example.com`.
    public var domain: String

    public init(url: URL, title: String, description: String? = nil, imageURL: URL? = nil, domain: String) {
        self.url = url
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.domain = domain
    }
}

/// A quoted post: shown with its author, text and media, but no card and no
/// quote of its own.
public indirect enum PeekQuote: Equatable, Sendable {
    case post(PeekPost)
    /// Deleted, blocked, or withheld from logged-out viewers.
    case unavailable
}

public struct PeekReplyContext: Equatable, Sendable {
    /// The post replied to, or nil when the site does not say which.
    public var link: PostPeekLink?
    /// `@handle`, or "a post".
    public var label: String

    public init(link: PostPeekLink?, label: String) {
        self.link = link
        self.label = label
    }
}

/// Why a post peek shows no post.
public enum PostPeekFailure: Error, Equatable, Sendable {
    /// The post does not exist or was deleted.
    case notFound
    /// The site does not show the post: a protected, blocked or removed
    /// account, or a post X does not embed.
    case unavailable
    /// The Bluesky author shows posts only to signed-in people
    /// (`!no-unauthenticated`).
    case loggedInOnly
    /// Bluesky's moderators hid the post or the account (`!hide`).
    case hiddenByModerators
    /// An HTTP status other than 200.
    case status(Int)
    /// The answer is not JSON of a shape the parser knows: the site changed
    /// its response.
    case badResponse
    /// The answer is not an HTTP response.
    case notHTTP
    /// The request failed: no network, a timeout, a TLS error.
    case network

    /// The notice the popover shows.
    public func message(site: PostPeekLink.Site) -> String {
        switch self {
        case .notFound:
            "This post does not exist or was deleted."
        case .unavailable:
            site == .bluesky
                ? "This post is unavailable. The account may be blocked, deactivated, or taken down."
                : "This post is unavailable to embed. It may be from a protected account, age-restricted, or removed."
        case .loggedInOnly:
            "The author shows their posts only to people signed in to Bluesky."
        case .hiddenByModerators:
            "Bluesky’s moderators have hidden this post."
        case let .status(code):
            "\(site.name) returned an error (HTTP \(code))."
        case .badResponse, .notHTTP:
            "This post could not be loaded."
        case .network:
            "This post could not be loaded. Check the network connection."
        }
    }

    /// True for a post the site holds back on purpose. The popover then
    /// offers "Open on <site>" rather than "Open in Browser".
    public var isWithheld: Bool {
        self == .loggedInOnly || self == .hiddenByModerators
    }
}

import Foundation

/// Reads one X or Bluesky post, and the images of the post peek popover
/// (MATRIX-201).
///
/// Credit: the endpoints, the X token and the Bluesky rules come from
/// post-peek by tsvb (https://github.com/tsvb/post-peek), MIT License,
/// re-implemented in Swift.
///
/// **These requests go from the Mac to X and Bluesky, not through the
/// homeserver.** The contract §11 row of 2026-11-19 (MATRIX-201) grants
/// them, only when the user clicks a post link:
/// - X: `GET https://cdn.syndication.twimg.com/tweet-result?id=<id>&lang=en&token=<token>&features=<flags>`,
///   the unofficial endpoint behind X's embed widgets. It can change without
///   notice. A changed answer is `PostPeekFailure.badResponse`, and the
///   popover then offers the browser.
/// - Bluesky: `GET https://public.api.bsky.app/xrpc/app.bsky.feed.getPostThread?uri=at://<actor>/app.bsky.feed.post/<rkey>&depth=0&parentHeight=1`,
///   the public AppView, with no account.
/// - Images: `https` only, from the media hosts of the two sites only
///   (`mediaHosts`), at most `maxImageBytes`.
///
/// No request carries a cookie, an account, or a Referer. The app's
/// transport (an ephemeral `URLSession`, see `PostPeekPresenter`) sets that
/// up. The transport is a parameter, so tests run from fixtures and never
/// touch the network.
///
/// Usage:
/// ```swift
/// let reader = PostPeekReader { try await session.data(for: $0) }
/// let post = try await reader.post(.x(id: "20"))
/// ```
public struct PostPeekReader: Sendable {
    /// Sends one request and returns the body and the response.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// The time a request may take before it fails.
    public static let timeout: TimeInterval = 10
    /// The largest image the popover loads.
    public static let maxImageBytes = 20 * 1024 * 1024
    /// The hosts an image may come from, also after a redirect.
    public static let mediaHosts = PostPeekParser.xMediaHosts.union(PostPeekParser.blueskyMediaHosts)

    static let xEndpoint = "https://cdn.syndication.twimg.com/tweet-result"
    static let blueskyEndpoint = "https://public.api.bsky.app/xrpc/app.bsky.feed.getPostThread"
    /// The feature flags X's embed code sends, as post-peek sends them.
    static let xFeatures = [
        "tfw_timeline_list:",
        "tfw_follower_count_sunset:true",
        "tfw_tweet_edit_backend:on",
        "tfw_refsrc_session:on",
        "tfw_fosnr_soft_interventions_enabled:on",
        "tfw_show_birdwatch_pivots_enabled:on",
        "tfw_show_business_verified_badge:on",
        "tfw_duplicate_scribes_to_settings:on",
        "tfw_use_profile_image_shape_enabled:on",
        "tfw_show_blue_verified_badge:on",
        "tfw_legacy_timeline_sunset:true",
        "tfw_show_gov_verified_badge:on",
        "tfw_show_business_affiliate_badge:on",
        "tfw_tweet_edit_frontend:on",
    ].joined(separator: ";")

    private let transport: Transport

    public init(transport: @escaping Transport) {
        self.transport = transport
    }

    /// The post of `link`.
    ///
    /// - Throws: `PostPeekFailure`, or the transport's error.
    public func post(_ link: PostPeekLink) async throws -> PeekPost {
        let (data, response) = try await transport(Self.request(for: link))
        guard let http = response as? HTTPURLResponse else { throw PostPeekFailure.notHTTP }
        switch link {
        case .x:
            if http.statusCode == 404 { throw PostPeekFailure.notFound }
            guard http.statusCode == 200 else { throw PostPeekFailure.status(http.statusCode) }
            return try PostPeekParser.xPost(from: data)
        case .bluesky:
            guard http.statusCode == 200 else {
                // The AppView answers a missing post with 400 and the error
                // name `NotFound`.
                let error = try? JSONDecoder().decode(JSONValue.self, from: data)
                if error?["error"]?.string == "NotFound" { throw PostPeekFailure.notFound }
                throw PostPeekFailure.status(http.statusCode)
            }
            return try PostPeekParser.blueskyPost(from: data)
        }
    }

    /// The bytes of the image at `url`.
    ///
    /// - Throws: `PostPeekFailure.badResponse` for a URL off the media hosts
    ///   (before or after a redirect), an image larger than `maxImageBytes`,
    ///   or bytes that are not an image. `status` for a status other than
    ///   200. Or the transport's error.
    public func image(at url: URL) async throws -> Data {
        guard Self.isMediaURL(url) else { throw PostPeekFailure.badResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = "GET"
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw PostPeekFailure.notHTTP }
        guard http.statusCode == 200 else { throw PostPeekFailure.status(http.statusCode) }
        guard http.url.map(Self.isMediaURL) ?? true, data.count <= Self.maxImageBytes, Self.isImage(data) else {
            throw PostPeekFailure.badResponse
        }
        return data
    }

    /// The request for `link`: a `GET` with `Accept: application/json`, no
    /// local cache, and a timeout of `timeout`.
    public static func request(for link: PostPeekLink) throws -> URLRequest {
        var components: URLComponents?
        switch link {
        case let .x(id):
            guard PostPeekLink.isXID(id), let token = PostPeekXToken.token(for: id) else { throw PostPeekFailure.notFound }
            components = URLComponents(string: xEndpoint)
            components?.queryItems = [
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "lang", value: "en"),
                URLQueryItem(name: "token", value: token),
                URLQueryItem(name: "features", value: xFeatures),
            ]
        case let .bluesky(actor, rkey):
            guard PostPeekLink.isBlueskyActor(actor), PostPeekLink.isRecordKey(rkey) else { throw PostPeekFailure.notFound }
            components = URLComponents(string: blueskyEndpoint)
            components?.queryItems = [
                URLQueryItem(name: "uri", value: "at://\(actor)/app.bsky.feed.post/\(rkey)"),
                URLQueryItem(name: "depth", value: "0"),
                URLQueryItem(name: "parentHeight", value: "1"),
            ]
        }
        // `URLQueryItem` leaves `:` and `;` as they are. Both are allowed in
        // a query, and the two endpoints read them as post-peek sends them.
        guard let url = components?.url else { throw PostPeekFailure.notFound }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// True for an `https` URL on one of `mediaHosts`.
    public static func isMediaURL(_ url: URL) -> Bool {
        PostPeekParser.mediaURL(url.absoluteString, hosts: mediaHosts) != nil
    }

    /// True if the first bytes are those of a JPEG, PNG, GIF or WebP file.
    /// A Bluesky video thumbnail comes as `application/octet-stream`, so the
    /// content type cannot say.
    static func isImage(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        func at(_ index: Int, _ expected: [UInt8]) -> Bool {
            bytes.count >= index + expected.count && Array(bytes[index ..< index + expected.count]) == expected
        }
        return at(0, [0xFF, 0xD8, 0xFF])
            || at(0, [0x89, 0x50, 0x4E, 0x47])
            || at(0, [0x47, 0x49, 0x46, 0x38])
            || (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50]))
    }

    /// A short name for an error, safe for the log: the case of a
    /// `PostPeekFailure`, else the error's domain and code.
    public static func logName(of error: Error) -> String {
        if let failure = error as? PostPeekFailure {
            return String(describing: failure)
        }
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }
}

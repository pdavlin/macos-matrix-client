import Foundation

/// Reads the URL preview of one Spotify link from the user's homeserver, for
/// the title of a music link (MATRIX-191).
///
/// **This is the second Matrix HTTP request that the app makes outside
/// matrix-rust-sdk** (the first is `RoomStateReader`). The contract §11 row
/// of 2026-11-18 (MATRIX-191) grants it: the pinned SDK (26.04.01) has no URL
/// preview call, so the app makes one authenticated, read-only
/// `GET /_matrix/client/v1/media/preview_url?url=<link>`. The homeserver
/// fetches the page, not the app. The server allows previews for
/// `open.spotify.com` only (`/etc/matrix-synapse/conf.d/url-preview.yaml`),
/// so any other URL gets a 403. The call reads display data only. It never
/// writes, and it does no sync, crypto, or timeline work. Remove this type
/// when an SDK bump gives a preview call. Do not add a second request here,
/// and do not add a second user without a contract row.
///
/// The access token goes only into the `Authorization` header of a request to
/// the homeserver URL of the SDK session. An error of this type holds no
/// token, no URL, and no response body, so it is safe to log.
///
/// The transport is a parameter. The app passes a `URLSession` call (see
/// `Core`), and a test passes a stub, so no test touches the network.
///
/// Usage:
/// ```swift
/// let reader = MusicLinkPreviewReader { try await session.data(for: $0) }
/// let json = try await reader.preview(of: link.canonicalURL, homeserverURL: url, accessToken: token)
/// ```
public struct MusicLinkPreviewReader: Sendable {
    /// Sends one request and returns the body and the response.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public enum Failure: Error, Equatable {
        /// The session's homeserver URL is not an `http` or `https` URL with
        /// a host.
        case badHomeserverURL
        /// The link to preview is not an `https` URL.
        case badLink
        /// The homeserver answered with a status other than 200. A 403 is a
        /// link that the server's preview settings block.
        case status(Int)
        /// The answer is not an HTTP response.
        case notHTTP
    }

    private let transport: Transport

    public init(transport: @escaping Transport) {
        self.transport = transport
    }

    /// The preview of `link`: the body of the homeserver's answer, a JSON
    /// object of Open Graph keys (`MusicLinkTitle.parse`).
    ///
    /// - Parameters:
    ///   - link: The link to preview, an `https` URL.
    ///   - homeserverURL: The homeserver URL of the SDK session.
    ///   - accessToken: The access token of the SDK session.
    /// - Throws: `Failure`, or the transport's error.
    public func preview(of link: URL, homeserverURL: String, accessToken: String) async throws -> Data {
        let request = try Self.request(link: link, homeserverURL: homeserverURL, accessToken: accessToken)
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw Failure.notHTTP }
        guard http.statusCode == 200 else { throw Failure.status(http.statusCode) }
        return data
    }

    /// The request: `GET {homeserver}/_matrix/client/v1/media/preview_url`
    /// with the query `url=<link>`, all reserved characters of the link
    /// encoded, and the headers `Authorization: Bearer <token>` and
    /// `Accept: application/json`, with no use of a local URL cache.
    public static func request(link: URL, homeserverURL: String, accessToken: String) throws -> URLRequest {
        guard link.scheme?.lowercased() == "https",
              let value = link.absoluteString.addingPercentEncoding(withAllowedCharacters: unreservedCharacters)
        else { throw Failure.badLink }
        guard var components = URLComponents(string: homeserverURL),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty
        else { throw Failure.badHomeserverURL }
        var base = components.percentEncodedPath
        while base.hasSuffix("/") {
            base.removeLast()
        }
        components.percentEncodedPath = "\(base)/_matrix/client/v1/media/preview_url"
        components.percentEncodedQuery = "url=\(value)"
        components.fragment = nil
        guard let url = components.url else { throw Failure.badHomeserverURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// A short name for an error, safe for the log: the case of a `Failure`,
    /// else the error's domain and code. Never the description, which can
    /// hold a URL.
    public static func logName(of error: Error) -> String {
        if let failure = error as? Failure {
            return String(describing: failure)
        }
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }

    private static let unreservedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}

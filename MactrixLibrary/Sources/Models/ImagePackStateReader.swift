import Foundation

/// Reads the state of one room from the user's homeserver, for the image
/// packs of a workspace space (MATRIX-155).
///
/// **This is the only Matrix HTTP call that the app makes outside
/// matrix-rust-sdk.** It is the bounded exception to hard rule 1 that
/// `docs/PROJECT_CONTRACT.md` §11 grants in the row of 2026-11-13 (MATRIX-151,
/// decision b): the pinned SDK (26.04.01) has no read of room state, so the
/// app makes one authenticated, read-only
/// `GET /_matrix/client/v3/rooms/{roomId}/state`. The call reads display data
/// only. It never writes, and it does no sync, crypto, or timeline work.
/// Remove this type when an SDK bump gives a state read. Do not add a second
/// request here.
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
/// let reader = ImagePackStateReader { try await session.data(for: $0) }
/// let state = try await reader.state(of: spaceId, homeserverURL: url, accessToken: token)
/// ```
public struct ImagePackStateReader: Sendable {
    /// Sends one request and returns the body and the response.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public enum Failure: Error, Equatable {
        /// The session's homeserver URL is not an `http` or `https` URL with
        /// a host.
        case badHomeserverURL
        /// The homeserver answered with a status other than 200.
        case status(Int)
        /// The answer is not an HTTP response.
        case notHTTP
    }

    private let transport: Transport

    public init(transport: @escaping Transport) {
        self.transport = transport
    }

    /// The state of `roomId`: the body of the homeserver's answer, a JSON
    /// array of state events.
    ///
    /// - Parameters:
    ///   - roomId: The room. The user must be a member.
    ///   - homeserverURL: The homeserver URL of the SDK session.
    ///   - accessToken: The access token of the SDK session.
    /// - Throws: `Failure`, or the transport's error.
    public func state(of roomId: String, homeserverURL: String, accessToken: String) async throws -> Data {
        let request = try Self.request(roomId: roomId, homeserverURL: homeserverURL, accessToken: accessToken)
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw Failure.notHTTP }
        guard http.statusCode == 200 else { throw Failure.status(http.statusCode) }
        return data
    }

    /// The request: `GET {homeserver}/_matrix/client/v3/rooms/{roomId}/state`
    /// with the headers `Authorization: Bearer <token>` and
    /// `Accept: application/json`, and with no use of a local URL cache.
    public static func request(roomId: String, homeserverURL: String, accessToken: String) throws -> URLRequest {
        guard var components = URLComponents(string: homeserverURL),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty,
              let room = roomId.addingPercentEncoding(withAllowedCharacters: unreservedCharacters)
        else { throw Failure.badHomeserverURL }
        var base = components.percentEncodedPath
        while base.hasSuffix("/") {
            base.removeLast()
        }
        components.percentEncodedPath = "\(base)/_matrix/client/v3/rooms/\(room)/state"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw Failure.badHomeserverURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static let unreservedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}

import Foundation
import Models
import Testing

/// MATRIX-191: the second request outside the SDK, the URL preview of a
/// Spotify link. A stub transport stands in for the network.
struct MusicLinkPreviewReaderTests {
    private static let token = "syt_secret_token"

    private func link(_ string: String = "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=abc") throws -> URL {
        try #require(URL(string: string))
    }

    private func response(_ status: Int) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://matrix.example.org/"))
        return try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
    }

    @Test func theRequestIsAnAuthenticatedGetOfThePreview() throws {
        let request = try MusicLinkPreviewReader.request(
            link: link(),
            homeserverURL: "https://matrix.example.org/",
            accessToken: Self.token
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString
            == "https://matrix.example.org/_matrix/client/v1/media/preview_url"
            + "?url=https%3A%2F%2Fopen.spotify.com%2Ftrack%2F4cOdK2wGLETKBW3PvgPWqT%3Fsi%3Dabc")
        #expect(request.allHTTPHeaderFields == ["Authorization": "Bearer \(Self.token)", "Accept": "application/json"])
        #expect(request.httpBody == nil)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func theQueryDecodesToTheLink() throws {
        let request = try MusicLinkPreviewReader.request(
            link: link(),
            homeserverURL: "https://matrix.example.org",
            accessToken: Self.token
        )
        let url = try #require(request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items == [URLQueryItem(name: "url", value: "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=abc")])
    }

    @Test func theRequestKeepsAHomeserverPathPrefixAndDropsItsQuery() throws {
        let request = try MusicLinkPreviewReader.request(
            link: link("https://open.spotify.com/album/6N9PS4QXF1D0OWPk0Sxtb4"),
            homeserverURL: "http://localhost:8008/base/?x=1#y",
            accessToken: Self.token
        )
        #expect(request.url?.absoluteString == "http://localhost:8008/base/_matrix/client/v1/media/preview_url"
            + "?url=https%3A%2F%2Fopen.spotify.com%2Falbum%2F6N9PS4QXF1D0OWPk0Sxtb4")
    }

    @Test func aHomeserverURLThatIsNotHTTPIsRefused() throws {
        let link = try link()
        for bad in ["", "matrix.example.org", "file:///etc/passwd", "ftp://example.org", "https://"] {
            #expect(throws: MusicLinkPreviewReader.Failure.badHomeserverURL) {
                try MusicLinkPreviewReader.request(link: link, homeserverURL: bad, accessToken: Self.token)
            }
        }
    }

    @Test func aLinkThatIsNotHTTPSIsRefused() throws {
        for bad in ["spotify:track:4cOdK2wGLETKBW3PvgPWqT", "http://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"] {
            let url = try link(bad)
            #expect(throws: MusicLinkPreviewReader.Failure.badLink) {
                try MusicLinkPreviewReader.request(link: url, homeserverURL: "https://matrix.example.org", accessToken: Self.token)
            }
        }
    }

    @Test func aGoodAnswerGivesTheBody() async throws {
        let ok = try response(200)
        let reader = MusicLinkPreviewReader { request in
            #expect(request.url?.host() == "matrix.example.org")
            return (Data(MusicLinkTitleTests.trackJSON.utf8), ok)
        }
        let body = try await reader.preview(of: link(), homeserverURL: "https://matrix.example.org", accessToken: Self.token)
        #expect(MusicLinkTitle.parse(body, kind: .song)?.name == "Never Gonna Give You Up")
    }

    @Test(arguments: [403, 404, 500])
    func anErrorStatusThrowsItAndHoldsNoToken(status: Int) async throws {
        let answer = try response(status)
        let reader = MusicLinkPreviewReader { _ in
            (Data(#"{"errcode":"M_FORBIDDEN","error":"URL blocked by url pattern blocklist entry"}"#.utf8), answer)
        }
        do {
            _ = try await reader.preview(of: link(), homeserverURL: "https://matrix.example.org", accessToken: Self.token)
            Issue.record("expected an error")
        } catch {
            #expect(error as? MusicLinkPreviewReader.Failure == .status(status))
            #expect(!String(describing: error).contains(Self.token))
            #expect(!String(reflecting: error).contains(Self.token))
            #expect(!MusicLinkPreviewReader.logName(of: error).contains(Self.token))
            #expect(!MusicLinkPreviewReader.logName(of: error).contains("spotify"))
        }
    }

    @Test func aTransportErrorLogsByDomainAndCodeOnly() async throws {
        let reader = MusicLinkPreviewReader { request in
            throw URLError(.notConnectedToInternet, userInfo: [NSURLErrorFailingURLErrorKey: request.url as Any])
        }
        do {
            _ = try await reader.preview(of: link(), homeserverURL: "https://matrix.example.org", accessToken: Self.token)
            Issue.record("expected an error")
        } catch {
            let name = MusicLinkPreviewReader.logName(of: error)
            #expect(name == "\(NSURLErrorDomain) \(URLError.notConnectedToInternet.rawValue)")
            #expect(!name.contains(Self.token))
        }
    }

    @Test func anAnswerThatIsNotHTTPThrows() async throws {
        let plain = try URLResponse(url: link(), mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        let reader = MusicLinkPreviewReader { _ in (Data(), plain) }
        await #expect(throws: MusicLinkPreviewReader.Failure.notHTTP) {
            try await reader.preview(of: link(), homeserverURL: "https://matrix.example.org", accessToken: Self.token)
        }
    }
}

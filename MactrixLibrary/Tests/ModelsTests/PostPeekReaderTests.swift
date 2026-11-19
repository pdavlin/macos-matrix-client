import Foundation
@testable import Models
import Testing

/// MATRIX-201: the post peek's requests to X and Bluesky. A stub transport
/// stands in for the network.
struct PostPeekReaderTests {
    private static func response(_ status: Int, url: String = "https://example.org/") throws -> HTTPURLResponse {
        let responseURL = try #require(URL(string: url))
        return try #require(HTTPURLResponse(url: responseURL, statusCode: status, httpVersion: nil, headerFields: nil))
    }

    private static func reader(status: Int, body: Data, finalURL: String? = nil) -> PostPeekReader {
        PostPeekReader { request in
            try (body, response(status, url: finalURL ?? request.url?.absoluteString ?? "https://example.org/"))
        }
    }

    @Test func theXRequestCarriesTheToken() throws {
        let request = try PostPeekReader.request(for: .x(id: "20"))
        let components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.scheme == "https")
        #expect(components.host == "cdn.syndication.twimg.com")
        #expect(components.path == "/tweet-result")
        #expect(items["id"] == "20")
        #expect(items["lang"] == "en")
        #expect(items["token"] == "6dq1a2xwd93")
        #expect(items["features"]?.hasPrefix("tfw_timeline_list:;") == true)
        #expect(request.httpMethod == "GET")
        #expect(request.allHTTPHeaderFields == ["Accept": "application/json"])
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.timeoutInterval == PostPeekReader.timeout)
    }

    @Test func theBlueskyRequestBuildsTheATURI() throws {
        let request = try PostPeekReader.request(for: .bluesky(actor: "bsky.app", rkey: "3n27yge3hys24"))
        let components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.host == "public.api.bsky.app")
        #expect(components.path == "/xrpc/app.bsky.feed.getPostThread")
        #expect(items == ["uri": "at://bsky.app/app.bsky.feed.post/3n27yge3hys24", "depth": "0", "parentHeight": "1"])
        #expect(request.allHTTPHeaderFields == ["Accept": "application/json"])
    }

    @Test func badPartsMakeNoRequest() {
        #expect(throws: PostPeekFailure.notFound) { try PostPeekReader.request(for: .x(id: "12a")) }
        #expect(throws: PostPeekFailure.notFound) { try PostPeekReader.request(for: .bluesky(actor: "a b", rkey: "x")) }
    }

    @Test func anXPostReads() async throws {
        let post = try await Self.reader(status: 200, body: PostPeekParserTests.fixture("x-jack-20")).post(.x(id: "20"))
        #expect(post.plainText == "just setting up my twttr")
    }

    @Test func statusesMapToFailures() async throws {
        await #expect(throws: PostPeekFailure.notFound) {
            try await Self.reader(status: 404, body: Data()).post(.x(id: "20"))
        }
        await #expect(throws: PostPeekFailure.status(429)) {
            try await Self.reader(status: 429, body: Data()).post(.x(id: "20"))
        }
        let notFound = Data(#"{"error":"NotFound","message":"Post not found"}"#.utf8)
        await #expect(throws: PostPeekFailure.notFound) {
            try await Self.reader(status: 400, body: notFound).post(.bluesky(actor: "bsky.app", rkey: "3zzz"))
        }
        await #expect(throws: PostPeekFailure.status(502)) {
            try await Self.reader(status: 502, body: Data()).post(.bluesky(actor: "bsky.app", rkey: "3zzz"))
        }
    }

    @Test func aBlueskyPostReads() async throws {
        let reader = try Self.reader(status: 200, body: PostPeekParserTests.fixture("bsky-quote-3n27yge3hys24"))
        let post = try await reader.post(.bluesky(actor: "bsky.app", rkey: "3n27yge3hys24"))
        #expect(post.author.handle == "bsky.app")
    }

    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    @Test func imagesComeOnlyFromTheMediaHosts() async throws {
        let good = try #require(URL(string: "https://pbs.twimg.com/media/a.jpg"))
        #expect(try await Self.reader(status: 200, body: Self.png).image(at: good) == Self.png)

        for bad in ["http://pbs.twimg.com/media/a.jpg", "https://evil.example.com/a.jpg"] {
            let url = try #require(URL(string: bad))
            await #expect(throws: PostPeekFailure.badResponse) {
                try await Self.reader(status: 200, body: Self.png).image(at: url)
            }
        }
        // A redirect off the media hosts.
        await #expect(throws: PostPeekFailure.badResponse) {
            try await Self.reader(status: 200, body: Self.png, finalURL: "https://evil.example.com/a.jpg").image(at: good)
        }
        // Bytes that are not an image.
        await #expect(throws: PostPeekFailure.badResponse) {
            try await Self.reader(status: 200, body: Data("<html>".utf8)).image(at: good)
        }
    }

    @Test func imageSniffing() {
        #expect(PostPeekReader.isImage(Data([0xFF, 0xD8, 0xFF, 0xE0])))
        #expect(PostPeekReader.isImage(Data("GIF89a".utf8)))
        #expect(PostPeekReader.isImage(Data("RIFF\0\0\0\0WEBP".utf8)))
        #expect(!PostPeekReader.isImage(Data("RIFF\0\0\0\0WAVE".utf8)))
        #expect(!PostPeekReader.isImage(Data()))
    }
}

import Foundation
import Models
import Testing

/// MATRIX-201: the links a plain click opens in the post peek, and the X
/// syndication token.
struct PostPeekLinkTests {
    private func link(_ string: String) throws -> PostPeekLink? {
        try PostPeekLink(url: #require(URL(string: string)))
    }

    @Test(arguments: [
        ("https://x.com/jack/status/20", "20"),
        ("https://twitter.com/jack/status/20", "20"),
        ("https://mobile.twitter.com/jack/status/20", "20"),
        ("https://www.twitter.com/jack/status/20", "20"),
        ("http://x.com/jack/status/20", "20"),
        ("https://X.com/jack/status/20", "20"),
        ("https://x.com/jack/status/20/photo/1", "20"),
        ("https://x.com/jack/status/20?s=20&t=abc", "20"),
        ("https://x.com/jack/status/20#reply", "20"),
        ("https://twitter.com/jack/statuses/20", "20"),
        ("https://x.com/i/web/status/1585341984679469056", "1585341984679469056"),
        ("https://x.com/Some_User_1/status/1868687553328169316/", "1868687553328169316"),
    ])
    func xLinks(url: String, id: String) throws {
        #expect(try link(url) == .x(id: id))
    }

    @Test(arguments: [
        ("https://bsky.app/profile/bsky.app/post/3n27yge3hys24", "bsky.app", "3n27yge3hys24"),
        ("https://bsky.app/profile/did:plc:z72i7hdynmk6r22z27h6tvur/post/3n27yge3hys24", "did:plc:z72i7hdynmk6r22z27h6tvur", "3n27yge3hys24"),
        ("https://bsky.app/profile/did%3Aplc%3Az72i7hdynmk6r22z27h6tvur/post/3n27yge3hys24", "did:plc:z72i7hdynmk6r22z27h6tvur", "3n27yge3hys24"),
        ("https://bsky.app/profile/alice.example.com/post/3n27yge3hys24?ref=share", "alice.example.com", "3n27yge3hys24"),
        ("https://bsky.app/profile/alice.example.com/post/3n27yge3hys24/quotes", "alice.example.com", "3n27yge3hys24"),
    ])
    func blueskyLinks(url: String, actor: String, rkey: String) throws {
        #expect(try link(url) == .bluesky(actor: actor, rkey: rkey))
    }

    @Test(arguments: [
        "https://x.com/jack",
        "https://x.com/jack/status/",
        "https://x.com/jack/status/abc",
        "https://x.com/jack/likes/20",
        "https://x.com/a_user_name_that_is_too_long/status/20",
        "https://x.com/jack/status/12345678901234567890123456",
        "https://notx.com/jack/status/20",
        "https://x.com.evil.example/jack/status/20",
        "https://fxtwitter.com/jack/status/20",
        "ftp://x.com/jack/status/20",
        "https://example.com/jack/status/20",
        "https://bsky.app/profile/bsky.app",
        "https://bsky.app/profile/bsky.app/post/",
        "https://bsky.app/profile/bsky.app/lists/3abc",
        "https://bsky.app/profile/bad%20actor/post/3n27yge3hys24",
        "https://bsky.app/profile/bsky.app/post/bad%20key",
        "https://staging.bsky.app/profile/bsky.app/post/3n27yge3hys24",
        "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT",
    ])
    func otherLinks(url: String) throws {
        #expect(try link(url) == nil)
    }

    @Test func theWebURLOpensThePost() {
        #expect(PostPeekLink.x(id: "20").webURL.absoluteString == "https://x.com/i/web/status/20")
        #expect(PostPeekLink.bluesky(actor: "bsky.app", rkey: "3n27yge3hys24").webURL.absoluteString
            == "https://bsky.app/profile/bsky.app/post/3n27yge3hys24")
    }

    @Test func anAtURINamesABlueskyPost() {
        #expect(PostPeekLink(atURI: "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.post/3n27yge3hys24")
            == .bluesky(actor: "did:plc:z72i7hdynmk6r22z27h6tvur", rkey: "3n27yge3hys24"))
        #expect(PostPeekLink(atURI: "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/whats-hot") == nil)
        #expect(PostPeekLink(atURI: "https://bsky.app/profile/bsky.app/post/3n27yge3hys24") == nil)
    }

    @Test func theSwitchIsOnByDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "PostPeekLinkTests-\(UUID().uuidString)"))
        #expect(PostPeekPreferences.isOn(in: defaults))
        defaults.set(false, forKey: PostPeekPreferences.storageKey)
        #expect(!PostPeekPreferences.isOn(in: defaults))
    }

    /// The values JavaScript (Node 24, V8) gives for post-peek's
    /// `((Number(id) / 1e15) * Math.PI).toString(36).replace(/(0+|\.)/g, '')`.
    @Test(arguments: [
        ("20", "6dq1a2xwd93"),
        ("1", "bhi2ay3f28n"),
        ("1234567890", "6iio5bzbwyw"),
        ("463440424141459456", "14fxvks611f"),
        ("440322224407314432", "12fb9qdo78ad"),
        ("266031293945503744", "n7rfhxzwhkd"),
        ("1585341984679469056", "3uchycv2wqc"),
        ("1868687553328169316", "4j2nkzumdno"),
        ("1990000000000000000", "4tnrp481eua"),
        ("1000000000000000001", "2f9lc2ug9mm"),
        ("9999999999999999999", "o8nxcsgioad"),
    ])
    func theXTokenMatchesPostPeek(id: String, token: String) {
        #expect(PostPeekXToken.token(for: id) == token)
    }

    @Test func aTokenNeedsANumber() {
        #expect(PostPeekXToken.token(for: "abc") == nil)
    }
}

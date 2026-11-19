import Foundation
@testable import Models
import Testing

/// MATRIX-201: the X and Bluesky answers of the post peek, read from saved
/// fixtures.
///
/// `x-jack-20`, `x-photo-440322224407314432`, `bsky-images-3n2m24be4e223`
/// and `bsky-quote-3n27yge3hys24` are real answers of public posts, fetched
/// once on 2026-11-19. The `crafted` fixtures are those answers changed to
/// the documented shapes of the cases no public post shows on demand:
/// labels, replies, video, cards, tombstones.
struct PostPeekParserTests {
    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/PostPeek"))
        return try Data(contentsOf: url)
    }

    // MARK: X

    @Test func aTextPost() throws {
        let post = try PostPeekParser.xPost(from: Self.fixture("x-jack-20"))

        #expect(post.link == .x(id: "20"))
        #expect(post.url.absoluteString == "https://x.com/jack/status/20")
        #expect(post.author == PeekAuthor(
            name: "jack",
            handle: "jack",
            avatarURL: URL(string: "https://pbs.twimg.com/profile_images/1661201415899951105/azNjKOSH_normal.jpg"),
            profileURL: URL(string: "https://x.com/jack"),
            isVerified: true
        ))
        #expect(post.text == [PeekTextRun("just setting up my twttr")])
        #expect(post.photos.isEmpty && post.videos.isEmpty && post.card == nil && post.quote == nil && post.replyTo == nil)
        #expect(post.date == Date(timeIntervalSince1970: 1_142_974_214))
    }

    @Test func aPhotoPostDropsTheMediaLinkFromTheText() throws {
        let post = try PostPeekParser.xPost(from: Self.fixture("x-photo-440322224407314432"))

        #expect(post.text == [
            PeekTextRun("If only Bradley's arm was longer. Best photo ever. "),
            PeekTextRun("#oscars", link: URL(string: "https://x.com/hashtag/oscars")),
        ])
        let photoURL = try #require(URL(string: "https://pbs.twimg.com/media/BhxWutnCEAAtEQ6.jpg"))
        #expect(post.photos == [PeekPhoto(
            url: photoURL,
            aspectRatio: 1920.0 / 1080.0
        )])
        #expect(post.card == nil)
    }

    @Test func aReplyThatQuotes() throws {
        let post = try PostPeekParser.xPost(from: Self.fixture("x-crafted-reply-quote"))

        // The mention before the range is the reply's, not the text's. The
        // `&amp;` is unescaped. The trailing media link is gone.
        #expect(post.text == [
            PeekTextRun("❤️ this & more "),
            PeekTextRun("example.com/story", link: URL(string: "https://example.com/story")),
        ])
        #expect(post.replyTo == PeekReplyContext(link: .x(id: "20"), label: "@jack"))
        guard case let .post(quote)? = post.quote else {
            Issue.record("no quote")
            return
        }
        #expect(quote.link == .x(id: "440322224407314432"))
        #expect(quote.author.handle == "TheEllenShow")
        #expect(quote.photos.count == 1)
        #expect(quote.quote == nil && quote.card == nil)
    }

    @Test func aVideoPicksTheBestMP4OnTheMediaHosts() throws {
        let post = try PostPeekParser.xPost(from: Self.fixture("x-crafted-video"))

        #expect(post.text == [PeekTextRun("watch")])
        let videoURL = try #require(URL(string: "https://video.twimg.com/ext_tw_video/1/pu/vid/1280x720/high.mp4"))
        #expect(post.videos == [PeekVideo(
            url: videoURL,
            posterURL: URL(string: "https://pbs.twimg.com/ext_tw_video_thumb/1/pu/img/poster.jpg"),
            aspectRatio: 16.0 / 9.0
        )])
    }

    @Test func aLinkCard() throws {
        let post = try PostPeekParser.xPost(from: Self.fixture("x-crafted-card"))

        let cardURL = try #require(URL(string: "https://t.co/card"))
        #expect(post.card == PeekCard(
            url: cardURL,
            title: "An example page",
            description: "What the page says.",
            imageURL: URL(string: "https://pbs.twimg.com/card_img/1/thumb.jpg"),
            domain: "example.com"
        ))
    }

    @Test func aTombstoneIsUnavailable() throws {
        #expect(throws: PostPeekFailure.unavailable) { try PostPeekParser.xPost(from: Self.fixture("x-crafted-tombstone")) }
        #expect(throws: PostPeekFailure.unavailable) { try PostPeekParser.xPost(from: Data()) }
    }

    @Test func aChangedAnswerIsABadResponse() {
        #expect(throws: PostPeekFailure.badResponse) { try PostPeekParser.xPost(from: Data("<html>".utf8)) }
        #expect(throws: PostPeekFailure.badResponse) { try PostPeekParser.xPost(from: Data(#"{"id_str":"20"}"#.utf8)) }
        #expect(throws: PostPeekFailure.badResponse) { try PostPeekParser.xPost(from: Data("[]".utf8)) }
    }

    @Test func mediaOffTheMediaHostsIsDropped() throws {
        let json = #"""
        {"id_str":"5","text":"x","user":{"screen_name":"a","profile_image_url_https":"https://evil.example.com/a.jpg"},
         "photos":[{"url":"http://pbs.twimg.com/media/a.jpg"},{"url":"https://evil.example.com/b.jpg"}]}
        """#
        let post = try PostPeekParser.xPost(from: Data(json.utf8))
        #expect(post.author.avatarURL == nil)
        #expect(post.photos.isEmpty)
    }

    // MARK: Bluesky

    @Test func aBlueskyPostWithAnImageAndAMention() throws {
        let post = try PostPeekParser.blueskyPost(from: Self.fixture("bsky-images-3n2m24be4e223"))

        #expect(post.link == .bluesky(actor: "did:plc:z72i7hdynmk6r22z27h6tvur", rkey: "3n2m24be4e223"))
        #expect(post.url.absoluteString == "https://bsky.app/profile/bsky.app/post/3n2m24be4e223")
        #expect(post.author.name == "Bluesky")
        #expect(post.author.handle == "bsky.app")
        #expect(post.author.avatarURL?.host == "cdn.bsky.app")
        // The facet indexes UTF-8 bytes: the em dash before it is 3 bytes.
        let mention = try #require(post.text.last)
        #expect(mention == PeekTextRun("@germnetwork.com", link: URL(string: "https://bsky.app/profile/did:plc:4yvwfwxfz5sney4twepuzdu7")))
        #expect(post.plainText.hasPrefix("Encrypted DMs from your Bluesky profile—now for Android and iOS!"))
        #expect(post.photos.count == 1)
        #expect(post.photos.first?.url.absoluteString.contains("/feed_fullsize/") == true)
        #expect(post.photos.first?.aspectRatio == 1)
        #expect(post.mediaWarning == nil && !post.hasContentWarning)
    }

    @Test func aBlueskyQuote() throws {
        let post = try PostPeekParser.blueskyPost(from: Self.fixture("bsky-quote-3n27yge3hys24"))

        #expect(post.plainText == "I heard Bluesky gets all its breaking news from Flavor Flav")
        guard case let .post(quote)? = post.quote else {
            Issue.record("no quote")
            return
        }
        #expect(quote.link == .bluesky(actor: "did:plc:4ewnpnebeh7zuk5pbardaxqz", rkey: "3n27ufkokmk2p"))
        #expect(quote.author.handle == "flavorflav.bsky.social")
        #expect(quote.author.isVerified)
        #expect(quote.plainText == "Nationwide ground stop on all flights in the US.")
    }

    @Test func aBlueskyReplyNamesItsParent() throws {
        let post = try PostPeekParser.blueskyPost(from: Self.fixture("bsky-crafted-reply"))
        #expect(post.replyTo == PeekReplyContext(
            link: .bluesky(actor: "did:plc:z72i7hdynmk6r22z27h6tvur", rkey: "3n2m24be4e223"),
            label: "@bsky.app"
        ))
    }

    @Test func anAuthorHiddenFromLoggedOutViewersIsWithheld() throws {
        #expect(throws: PostPeekFailure.loggedInOnly) {
            try PostPeekParser.blueskyPost(from: Self.fixture("bsky-crafted-logged-in-only"))
        }
    }

    @Test func aPostOrAccountHiddenByModeratorsIsWithheld() throws {
        #expect(throws: PostPeekFailure.hiddenByModerators) {
            try PostPeekParser.blueskyPost(from: Self.fixture("bsky-crafted-moderator-hidden"))
        }
        #expect(throws: PostPeekFailure.hiddenByModerators) {
            try PostPeekParser.blueskyPost(from: Self.fixture("bsky-crafted-account-hidden"))
        }
    }

    @Test func aWithheldQuoteIsUnavailable() throws {
        let post = try PostPeekParser.blueskyPost(from: Self.fixture("bsky-crafted-withheld-quote"))
        #expect(post.quote == .unavailable)
    }

    @Test func labeledMediaStaysBehindAClick() throws {
        let post = try PostPeekParser.blueskyPost(from: Self.fixture("bsky-crafted-labeled-porn"))
        #expect(post.mediaWarning == "porn")
        #expect(!post.hasContentWarning)
        #expect(post.photos.count == 1)

        let warned = try PostPeekParser.blueskyPost(from: Self.fixture("bsky-crafted-warn"))
        #expect(warned.hasContentWarning)
    }

    @Test func aMissingBlueskyPostIsNotFound() throws {
        #expect(throws: PostPeekFailure.notFound) {
            try PostPeekParser.blueskyPost(from: Self.fixture("bsky-crafted-not-found"))
        }
        #expect(throws: PostPeekFailure.unavailable) {
            try PostPeekParser.blueskyPost(from: Data(#"{"thread":{"$type":"app.bsky.feed.defs#blockedPost"}}"#.utf8))
        }
        #expect(throws: PostPeekFailure.badResponse) { try PostPeekParser.blueskyPost(from: Data("{}".utf8)) }
    }

    @Test func linkTextThatNamesAnotherSiteSaysWhereItGoes() {
        #expect(PostPeekParser.namedHost("www.example.com/a…") == "example.com")
        #expect(PostPeekParser.namedHost("https://Example.com") == "example.com")
        #expect(PostPeekParser.namedHost("click here") == nil)
        #expect(PostPeekParser.namedHost("here") == nil)
    }

    // MARK: Base 36

    /// The values JavaScript (Node 24, V8) gives for `value.toString(radix)`.
    @Test(arguments: [
        (0.5, 36, "0.i"),
        (Double.pi, 36, "3.53i5ab8p5f"),
        (123.456, 36, "3f.gez4w97ry"),
        (1e21, 36, "5v1j4f4ds7c000"),
        (0.1, 36, "0.3lllllllllm"),
        (1.0 / 3.0, 36, "0.c"),
        (4980.4, 36, "3uc.eeeeeeed"),
        (255.99999999, 36, "73.zzzzze8cw"),
        (0.999999999999, 36, "0.zzzzzzzx6g9"),
        (1e-7, 36, "0.000061oezo085tl"),
        (-2.5, 36, "-2.i"),
        (0.1, 2, "0.0001100110011001100110011001100110011001100110011001101"),
    ])
    func radixStringMatchesJavaScript(value: Double, radix: Int, expected: String) {
        #expect(PostPeekXToken.radixString(value, radix: radix) == expected)
    }
}

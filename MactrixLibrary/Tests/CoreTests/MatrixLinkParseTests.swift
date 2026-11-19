@testable import Core
import Foundation
import MatrixRustSDK
import Models
import Testing

/// MATRIX-203: the SDK's parse (`parseMatrixEntityFrom(uri:)`) of the links
/// a message body holds, mapped to `MatrixLink`.
struct MatrixLinkParseTests {
    private static func parse(_ string: String) -> MatrixLink? {
        URL(string: string).flatMap(MatrixLink.init(url:))
    }

    /// The link mautrix-slack writes for a Slack message link.
    @Test func bridgedEventPermalink() {
        let link = Self.parse("https://matrix.to/#/!abc:davlin.io/$evt?via=davlin.io")
        #expect(link == .room(.id("!abc:davlin.io"), eventId: "$evt", via: ["davlin.io"]))
    }

    @Test func roomIdLink() {
        #expect(Self.parse("https://matrix.to/#/!abc:davlin.io") == .room(.id("!abc:davlin.io"), eventId: nil, via: []))
    }

    @Test func aliasLink() {
        #expect(Self.parse("https://matrix.to/#/%23general:davlin.io") == .room(.alias("#general:davlin.io"), eventId: nil, via: []))
    }

    @Test func userLink() {
        #expect(Self.parse("https://matrix.to/#/@seth:davlin.io") == .user(id: "@seth:davlin.io"))
    }

    @Test func matrixUri() {
        #expect(Self.parse("matrix:roomid/abc:davlin.io/e/evt") == .room(.id("!abc:davlin.io"), eventId: "$evt", via: []))
    }

    @Test(arguments: [
        "https://example.org/#/!abc:davlin.io",
        "https://x.com/jack/status/20",
        "https://davlin.slack.com/archives/C123/p1700000000000100",
    ])
    func otherLinksDoNotParse(_ string: String) {
        #expect(Self.parse(string) == nil)
    }
}

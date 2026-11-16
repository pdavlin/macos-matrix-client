import Foundation
@testable import Models
import Testing

/// MATRIX-162: a custom emoticon counts as an emoji in the jumbo rule.
///
/// The emoticon exists only in the HTML body, as an `<img>`. The plain body
/// of a bridged message holds `:name:`, which is text.
struct JumboEmoticonTests {
    /// The exact tag the Slack bridge writes.
    private static let parrot = #"<img data-mx-emoticon src="mxc://example.org/parrot" alt=":partyparrot:" title=":partyparrot:" height="32"/>"#
    /// The same tag as the SDK timeline gives it back, without the flag.
    private static let sanitized = #"<img src="mxc://example.org/parrot" alt=":partyparrot:" title=":partyparrot:" height="32">"#
    private static let thumb = "\u{1F44D}"

    private func kind(_ formatted: String, body: String = ":partyparrot:") -> JumboEmoji.Kind? {
        JumboEmoji.kind(body: body, formattedBody: formatted)
    }

    // MARK: - Jumbo

    @Test func oneEmoticonIsJumbo() {
        #expect(kind(Self.parrot) == .formatted)
        #expect(kind(Self.sanitized) == .formatted)
    }

    @Test(arguments: 1 ... 9)
    func upToNineEmoticonsAreJumbo(count: Int) {
        #expect(kind(String(repeating: Self.parrot, count: count)) == .formatted)
        #expect(kind(Array(repeating: Self.parrot, count: count).joined(separator: " ")) == .formatted)
    }

    @Test func unicodeAndEmoticonsCountTogether() {
        #expect(kind("\(Self.thumb) \(Self.parrot)\(Self.thumb)") == .formatted)
        let nine = String(repeating: Self.thumb, count: 4) + String(repeating: Self.parrot, count: 5)
        #expect(kind(nine) == .formatted)
        #expect(kind(nine + Self.thumb) == nil)
        #expect(kind(nine + Self.parrot) == nil)
    }

    @Test(arguments: [
        "<p>\(parrot)</p>",
        "<P>\(parrot)</P>",
        "<p>\(parrot)</p>\n<p>\(parrot)</p>",
        "\(parrot)<br>\(parrot)",
        "\(parrot)<br/>\(parrot)<br />",
        "<span>\(parrot)</span>",
        "<p><span> \(parrot) </span></p>\n",
        #"<img data-mx-emoticon src="mxc://example.org/parrot" alt=":partyparrot:"></img>"#,
        #"<IMG SRC='mxc://example.org/parrot' ALT=':partyparrot:'>"#,
    ])
    func tagsWithNoTextKeepTheBodyJumbo(formatted: String) {
        #expect(kind(formatted) == .formatted)
    }

    /// An HTML body of Unicode emoji in a paragraph is emoji-only too.
    @Test func unicodeEmojiInAParagraphIsJumbo() {
        #expect(kind("<p>\(Self.thumb)</p>", body: Self.thumb) == .formatted)
    }

    /// With no markup at all, the plain body draws, as before MATRIX-162.
    @Test func unicodeEmojiWithNoMarkupIsJumboText() {
        #expect(JumboEmoji.kind(body: Self.thumb, formattedBody: nil) == .text)
        #expect(JumboEmoji.kind(body: Self.thumb, formattedBody: " \(Self.thumb)\n") == .text)
    }

    // MARK: - Body size

    @Test func tenEmoticonsAreBodySize() {
        #expect(kind(String(repeating: Self.parrot, count: 10)) == nil)
    }

    @Test(arguments: [
        "nice \(parrot)",
        "\(parrot) nice",
        "\(parrot)x\(parrot)",
        "<p>\(parrot)</p><p>ok</p>",
        "\(parrot)&nbsp;",
        "\(parrot)&amp;",
        "\(parrot)\u{200B}",
        "\(parrot).",
    ])
    func anyOtherTextIsBodySize(formatted: String) {
        #expect(kind(formatted) == nil)
    }

    @Test(arguments: [
        "<b>\(parrot)</b>",
        "<a href=\"https://example.org\">\(parrot)</a>",
        "<h1>\(parrot)</h1>",
        "<code>\(parrot)</code>",
        "<blockquote>\(parrot)</blockquote>",
        "<mx-reply>\(parrot)</mx-reply>",
        "<span data-mx-spoiler>\(parrot)</span>",
        "<span data-mx-color=\"#ff0000\">\(parrot)</span>",
        "<p class=\"x\">\(parrot)</p>",
        "<!-- note -->\(parrot)",
        "<>\(parrot)",
    ])
    func anyOtherTagIsBodySize(formatted: String) {
        #expect(kind(formatted) == nil)
    }

    /// An `<img>` that is not a custom emoticon draws as its alt text.
    @Test(arguments: [
        #"<img src="https://tracker.example/e.png" alt=":e:">"#,
        #"<img data-mx-emoticon src="https://tracker.example/e.png" alt=":e:">"#,
        #"<img src="mxc://example.org/media" alt="a chart">"#,
        #"<img src="mxc://example.org/media">"#,
        #"<img data-mx-emoticon alt=":e:">"#,
        #"<img src="mxc://example.org/media" alt=":e:""#,
        #"<img src="mxc://example.org/media" alt="a>b:">"#,
        "<img src=\"mxc://example.org/media\" alt=\":\u{FFF9}:\">",
        #"<imgx src="mxc://example.org/media" alt=":e:">"#,
    ])
    func otherImagesAreBodySize(formatted: String) {
        #expect(kind(formatted) == nil)
        #expect(kind(Self.parrot + formatted) == nil)
    }

    @Test(arguments: ["", " ", "<p></p>", "<br>", "<span></span>", "<", "<p"])
    func aBodyWithNoEmojiIsBodySize(formatted: String) {
        #expect(kind(formatted) == nil)
    }

    /// `:name:` typed as plain text is text, with and without an HTML body.
    @Test func shortcodeTextIsBodySize() {
        #expect(JumboEmoji.kind(body: ":partyparrot:", formattedBody: nil) == nil)
        #expect(JumboEmoji.kind(body: ":partyparrot:", formattedBody: ":partyparrot:") == nil)
        #expect(JumboEmoji.kind(body: ":partyparrot:", formattedBody: "<p>:partyparrot:</p>") == nil)
    }

    /// The plain body does not decide for an HTML body: an emoji-only plain
    /// body with other text in the HTML body is body size.
    @Test func theFormattedBodyDecides() {
        #expect(JumboEmoji.kind(body: Self.thumb, formattedBody: "<b>\(Self.thumb)</b>") == nil)
        #expect(JumboEmoji.kind(body: Self.thumb, formattedBody: "\(Self.thumb) ok") == nil)
        #expect(JumboEmoji.kind(body: "ok", formattedBody: Self.parrot) == .formatted)
    }

    // MARK: - The tag reader

    @Test func tagReaderTakesOneWholeTagOnly() {
        #expect(EmoticonImageTag.isEmoticon(tag: Self.parrot))
        #expect(EmoticonImageTag.isEmoticon(tag: Self.sanitized))
        #expect(!EmoticonImageTag.isEmoticon(tag: " " + Self.parrot))
        #expect(!EmoticonImageTag.isEmoticon(tag: Self.parrot + "x"))
        #expect(!EmoticonImageTag.isEmoticon(tag: Self.parrot + Self.parrot))
        #expect(!EmoticonImageTag.isEmoticon(tag: "<p>"))
    }

    // MARK: - The height fingerprint

    @Test func geometryHoldsTheDecision() {
        let jumbo = MessageBodyGeometry(variant: "text", text: ":partyparrot:", formattedText: Self.parrot)
        #expect(jumbo.jumboEmoji == .formatted)
        #expect(jumbo.isJumboEmoji)

        let withWord = MessageBodyGeometry(variant: "text", text: "nice :partyparrot:", formattedText: "nice \(Self.parrot)")
        #expect(withWord.jumboEmoji == nil)
        // The flip is a change of the compared bodies, so the row is measured again.
        #expect(jumbo != withWord)

        #expect(MessageBodyGeometry(variant: "text", text: Self.thumb).jumboEmoji == .text)
        #expect(MessageBodyGeometry(variant: "notice", text: ":partyparrot:", formattedText: Self.parrot).jumboEmoji == nil)
    }

    // MARK: - Cost

    /// The scan stops at the first piece that is not an emoji, so a long
    /// prose body costs the same as a short one. The test reads where the
    /// scan stopped. It does not measure time.
    @Test func scanStopsAtTheFirstPieceThatIsNotAnEmoji() {
        let tail = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 2000)

        // `<p>`, then the first letter.
        let prose = "<p>" + tail + "</p>"
        let proseScan = JumboEmoji.scan(formattedBody: prose)
        #expect(!proseScan.isEmojiOnly)
        #expect(prose.distance(from: prose.startIndex, to: proseScan.stop) == 4)

        // An emoticon, a space, then the first letter.
        let afterEmoticon = Self.parrot + " " + tail
        let emoticonScan = JumboEmoji.scan(formattedBody: afterEmoticon)
        #expect(!emoticonScan.isEmojiOnly)
        #expect(afterEmoticon.distance(from: afterEmoticon.startIndex, to: emoticonScan.stop) == Self.parrot.count + 2)

        // A tag that is not allowed: the scan reads that tag and no more.
        let bold = "<b>" + tail + "</b>"
        #expect(bold.distance(from: bold.startIndex, to: JumboEmoji.scan(formattedBody: bold).stop) == 3)

        // The tenth emoji: the scan does not read the ninety after it.
        let many = String(repeating: Self.thumb, count: 100)
        let manyScan = JumboEmoji.scan(formattedBody: many)
        #expect(!manyScan.isEmojiOnly)
        #expect(many.distance(from: many.startIndex, to: manyScan.stop) == JumboEmoji.maximumCount + 1)

        // A jumbo body is read to its end.
        let nine = String(repeating: Self.parrot, count: 9)
        let nineScan = JumboEmoji.scan(formattedBody: nine)
        #expect(nineScan.isEmojiOnly)
        #expect(nineScan.stop == nine.endIndex)
    }
}

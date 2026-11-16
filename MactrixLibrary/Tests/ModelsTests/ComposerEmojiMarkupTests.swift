import Foundation
@testable import Models
import Testing

/// MATRIX-156: the send-time substitution of `:name:` tokens by emoticon
/// tags, in the markdown that goes to the SDK.
struct ComposerEmojiMarkupTests {
    private static let parrotURL = "mxc://example.org/parrot"
    private static let shipURL = "mxc://example.org/ship"

    private let packs = [
        ImagePack(key: "slack", displayName: "Work", emoji: [
            ImagePackEmoji(shortcode: "parrot", url: parrotURL),
            ImagePackEmoji(shortcode: "ship_it", url: shipURL),
            ImagePackEmoji(shortcode: "+1", url: "mxc://example.org/plus"),
        ]),
    ]

    private static let parrot =
        "<img data-mx-emoticon src=\"mxc://example.org/parrot\" alt=\":parrot:\" title=\":parrot:\" height=\"32\" />"
    private static let parrotAlone =
        "<img data-mx-emoticon src=\"mxc://example.org/parrot\" alt=\":parrot:\" title=\":parrot:\" height=\"32\"\n/>"
    private static let ship =
        "<img data-mx-emoticon src=\"mxc://example.org/ship\" alt=\":ship_it:\" title=\":ship_it:\" height=\"32\" />"

    private func resolve(_ markdown: String) -> String {
        ComposerEmojiMarkup.resolving(markdown: markdown, packs: packs)
    }

    // MARK: - Substitution

    @Test func tokenBecomesTag() {
        #expect(resolve("hello :parrot: there") == "hello \(Self.parrot) there")
    }

    @Test func eachTokenResolves() {
        #expect(resolve("go :ship_it: now :parrot:!") == "go \(Self.ship) now \(Self.parrot)!")
        #expect(resolve(":parrot::parrot: x") == "\(Self.parrot)\(Self.parrot) x")
    }

    @Test func tokenInEmphasisResolves() {
        #expect(resolve("**done :ship_it:** ok") == "**done \(Self.ship)** ok")
    }

    @Test func shortcodeWithPunctuationResolves() {
        let result = resolve("yes :+1: ok")
        #expect(result.contains("alt=\":+1:\""))
        #expect(result.hasPrefix("yes <img ") && result.hasSuffix(" /> ok"))
    }

    // MARK: - Byte-for-byte when nothing resolves

    @Test(arguments: [
        "plain text",
        "**bold** and _italic_ with a [link](https://example.org/a:b:c)",
        "unknown :not_in_pack: stays",
        "wrong case :Parrot: stays",
        "time 10:30:15 and a:parrot:b",
        "half :parrot and parrot: and : parrot :",
        "`:parrot:` in code",
        "```\n:parrot:\n```",
        "line one\r\nline two :nope:\r\n",
        "",
    ])
    func messageWithoutResolvedEmojiIsUnchanged(markdown: String) {
        let result = resolve(markdown)
        #expect(result == markdown)
        #expect(Array(result.utf8) == Array(markdown.utf8))
    }

    @Test func noPackChangesNothing() {
        let markdown = "hello :parrot: there"
        #expect(ComposerEmojiMarkup.resolving(markdown: markdown, packs: []) == markdown)
        let empty = [ImagePack(key: "k", displayName: nil, emoji: [])]
        #expect(ComposerEmojiMarkup.resolving(markdown: markdown, packs: empty) == markdown)
    }

    @Test func onlyTheGivenPacksResolve() {
        let other = [ImagePack(key: "b", displayName: nil, emoji: [ImagePackEmoji(shortcode: "wave", url: "mxc://b/wave")])]
        let markdown = "hi :parrot: :wave:"
        let result = ComposerEmojiMarkup.resolving(markdown: markdown, packs: other)
        #expect(result.contains(":parrot:"))
        #expect(!result.contains("example.org/parrot"))
        #expect(result.contains("src=\"mxc://b/wave\""))
    }

    @Test func firstPackWinsForASharedShortcode() {
        let two = packs + [ImagePack(key: "z", displayName: nil, emoji: [ImagePackEmoji(shortcode: "parrot", url: "mxc://z/other")])]
        #expect(ComposerEmojiMarkup.resolving(markdown: "a :parrot:", packs: two) == "a \(Self.parrot)")
    }

    // MARK: - Code, links, HTML, escapes

    @Test func inlineCodeIsNotSubstituted() {
        #expect(resolve("`:parrot:` and :parrot: x") == "`:parrot:` and \(Self.parrot) x")
        #expect(resolve("``a ` :parrot: `` :parrot: x") == "``a ` :parrot: `` \(Self.parrot) x")
    }

    @Test func unclosedBacktickIsText() {
        #expect(resolve("a ` b :parrot: c") == "a ` b \(Self.parrot) c")
    }

    @Test func fencedCodeBlockIsNotSubstituted() {
        let markdown = "see :parrot: x\n```swift\nlet a = \":parrot:\"\n```\nafter :parrot: x"
        let expected = "see \(Self.parrot) x\n```swift\nlet a = \":parrot:\"\n```\nafter \(Self.parrot) x"
        #expect(resolve(markdown) == expected)
    }

    @Test func tildeFenceAndUnclosedFenceAreCode() {
        #expect(resolve("a :parrot: b\n~~~\n:parrot:\n~~~") == "a \(Self.parrot) b\n~~~\n:parrot:\n~~~")
        #expect(resolve("a :parrot: b\n```\n:parrot:\nmore :parrot:") == "a \(Self.parrot) b\n```\n:parrot:\nmore :parrot:")
    }

    @Test func indentedCodeIsNotSubstituted() {
        #expect(resolve("a :parrot: b\n\n    :parrot: code\n\t:parrot:") == "a \(Self.parrot) b\n\n    :parrot: code\n\t:parrot:")
    }

    @Test func linkDestinationAndHtmlAreNotSubstituted() {
        #expect(resolve("[x](https://e.org/:parrot:) :parrot: y") == "[x](https://e.org/:parrot:) \(Self.parrot) y")
        #expect(resolve("<https://e.org/:parrot:> :parrot: y") == "<https://e.org/:parrot:> \(Self.parrot) y")
        #expect(resolve("<b title=\":parrot:\">b</b> :parrot: y") == "<b title=\":parrot:\">b</b> \(Self.parrot) y")
    }

    @Test func mentionPillKeepsItsLink() {
        let outgoing = MentionMarkdown.outgoingMessage(
            fromDraftText: "[Pat](https://matrix.to/#/@pat:example.org) :parrot: hi"
        ).resolvingEmoji(in: packs)
        #expect(outgoing.markdown == "[Pat](https://matrix.to/#/@pat:example.org) \(Self.parrot) hi")
        #expect(outgoing.mentionedUserIds == ["@pat:example.org"])
    }

    @Test func backslashEscapeKeepsTheToken() {
        #expect(resolve("\\:parrot: and :parrot: x") == "\\:parrot: and \(Self.parrot) x")
    }

    @Test func tokenAfterALetterOrDigitIsText() {
        #expect(resolve("key:parrot: and :parrot: x") == "key:parrot: and \(Self.parrot) x")
    }

    // MARK: - A tag alone on its line

    @Test func tagAloneOnALineBreaksBeforeItsEnd() {
        // One complete tag alone on a line starts a markdown HTML block, and
        // the next line would lose its formatting.
        #expect(resolve(":parrot:") == Self.parrotAlone)
        #expect(resolve(":parrot:\n**bold**") == "\(Self.parrotAlone)\n**bold**")
        #expect(resolve("- :parrot:  \n> :parrot:") == "- \(Self.parrotAlone)  \n> \(Self.parrotAlone)")
    }

    @Test func tagWithOtherContentOnItsLineStaysOnOneLine() {
        #expect(resolve("# :parrot:") == "# \(Self.parrot)")
        #expect(resolve(":parrot: :parrot:") == "\(Self.parrot) \(Self.parrot)")
        #expect(resolve("ok :parrot:") == "ok \(Self.parrot)")
    }

    // MARK: - Escaping

    @Test func urlAndNameAreAttributeEscaped() {
        let tag = ComposerEmojiMarkup.tag(shortcode: "a\"b<c>&d", url: "mxc://e.org/x?a=1&b=\"2\"")
        #expect(tag == "<img data-mx-emoticon src=\"mxc://e.org/x?a=1&amp;b=&quot;2&quot;\" "
            + "alt=\":a&quot;b&lt;c&gt;&amp;d:\" title=\":a&quot;b&lt;c&gt;&amp;d:\" height=\"32\" />")
    }

    @Test func escapedNameResolvesFromThePack() {
        let odd = [ImagePack(key: "k", displayName: nil, emoji: [ImagePackEmoji(shortcode: "a&b", url: "mxc://e.org/q\"x")])]
        let result = ComposerEmojiMarkup.resolving(markdown: "x :a&b: y", packs: odd)
        #expect(result == "x <img data-mx-emoticon src=\"mxc://e.org/q&quot;x\" alt=\":a&amp;b:\" title=\":a&amp;b:\" height=\"32\" /> y")
    }

    @Test func unsafeEmojiDoNotResolve() {
        let bad = [ImagePack(key: "k", displayName: nil, emoji: [
            ImagePackEmoji(shortcode: "http", url: "https://example.org/a.png"),
            ImagePackEmoji(shortcode: "space", url: "mxc://e.org/a b"),
            ImagePackEmoji(shortcode: "tick`", url: "mxc://e.org/t"),
            ImagePackEmoji(shortcode: "a:b", url: "mxc://e.org/c"),
        ])]
        #expect(ComposerEmojiMarkup.shortcodeURLs(in: bad).isEmpty)
        let markdown = "x :http: :space: :a:b: y"
        #expect(ComposerEmojiMarkup.resolving(markdown: markdown, packs: bad) == markdown)
    }

    // MARK: - Sent body back to draft text

    @Test func sentBodyReadsAsTokensAgain() {
        let draft = "hello :parrot: there\n:ship_it:\n**b**"
        let body = resolve(draft)
        #expect(body != draft)
        #expect(ComposerEmojiMarkup.draftText(fromBody: body) == draft)
    }

    @Test func bodyWithTwoTagsReadsAsTwoTokens() {
        let body = "a \(Self.parrot) b \(Self.ship) c"
        #expect(ComposerEmojiMarkup.draftText(fromBody: body) == "a :parrot: b :ship_it: c")
        #expect(ComposerEmojiMarkup.draftText(fromBody: "\(Self.parrotAlone)\n\(Self.parrot)") == ":parrot:\n:parrot:")
    }

    @Test(arguments: [
        "see <img src=\"x.png\"> here",
        "a literal <img data-mx-emoticon in a sentence",
        "<img data-mx-emoticon src=\"mxc://e.org/x\" alt=\"parrot\" title=\"parrot\" height=\"32\" />",
        "<img data-mx-emoticon src=\"mxc://e.org/x\" alt=\":parrot:\" title=\":parrot:\" height=\"64\" />",
        "<img data-mx-emoticon src=\"mxc://e.org/x\" alt=\":parrot:\">",
    ])
    func imageTagThatTheComposerDidNotMakeStaysAsTyped(body: String) {
        #expect(ComposerEmojiMarkup.draftText(fromBody: body) == body)
    }

    @Test func typedImageTagBesideASentTagStaysAsTyped() {
        let typed = "<img src=\"mxc://e.org/photo\" alt=\":not_ours:\">"
        #expect(ComposerEmojiMarkup.draftText(fromBody: "\(typed) and \(Self.parrot)") == "\(typed) and :parrot:")
    }

    @Test func escapedNameRoundTrips() {
        let body = "x " + ComposerEmojiMarkup.tag(shortcode: "a&b", url: "mxc://e.org/q") + " y"
        #expect(ComposerEmojiMarkup.draftText(fromBody: body) == "x :a&b: y")
    }

    @Test func otherHtmlInABodyIsKept() {
        let body = "a <img src=\"mxc://e.org/x\" alt=\"photo\" /> b <img data-mx-emoticon src=\"https://e.org\" alt=\":x:\" />"
        #expect(ComposerEmojiMarkup.draftText(fromBody: body) == body)
        #expect(ComposerEmojiMarkup.draftText(fromBody: "plain") == "plain")
    }

    // MARK: - Outgoing content

    @Test func editContentResolvesMessagesAndKeepsCaptions() {
        let message = ComposerEditContent.message(MentionMarkdown.outgoingMessage(fromDraftText: "ok :parrot: x"))
        guard case let .message(outgoing) = message.resolvingEmoji(in: packs) else {
            Issue.record("the edit is not a message")
            return
        }
        #expect(outgoing.markdown == "ok \(Self.parrot) x")

        let caption = ComposerEditContent.caption(text: "ok :parrot:", mentionedUserIds: [])
        #expect(caption.resolvingEmoji(in: packs) == caption)
    }
}

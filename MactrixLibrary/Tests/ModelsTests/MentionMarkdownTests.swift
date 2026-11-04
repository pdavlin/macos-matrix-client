@testable import Models
import Testing

/// MATRIX-105 (D-6): chips become `matrix.to` pill links on send, with the
/// mentioned users in `m.mentions`. Drafts keep chips through the same pill
/// form.
struct MentionMarkdownTests {
    private let alice = MentionTarget(userId: "@alice:example.org", displayName: "Alice")
    private let bob = MentionTarget(userId: "@bob:example.org", displayName: "Bob")

    // MARK: - Chips to markdown

    @Test func chipBecomesPillLink() {
        let segments: [ComposerSegment] = [.text("hi "), .mention(alice), .text(" there")]
        #expect(MentionMarkdown.messageMarkdown(for: segments)
            == "hi [Alice](https://matrix.to/#/@alice:example.org) there")
    }

    @Test func markdownCharactersInNameAreEscaped() {
        let target = MentionTarget(userId: "@x:example.org", displayName: "*Star* [Bot]_v2 `x` <tag> ~a~ & \\")
        let markdown = MentionMarkdown.messageMarkdown(for: [.mention(target)])
        #expect(markdown
            == "[\\*Star\\* \\[Bot\\]\\_v2 \\`x\\` \\<tag\\> \\~a\\~ \\& \\\\](https://matrix.to/#/@x:example.org)")
    }

    @Test func plainPunctuationInNameIsNotEscaped() {
        let target = MentionTarget(userId: "@x:example.org", displayName: "Dr. Who (Tardis) #1!")
        #expect(MentionMarkdown.messageMarkdown(for: [.mention(target)])
            == "[Dr. Who (Tardis) #1!](https://matrix.to/#/@x:example.org)")
    }

    @Test func emptyDisplayNameUsesUserId() {
        let target = MentionTarget(userId: "@carol:example.org", displayName: nil)
        #expect(MentionMarkdown.messageMarkdown(for: [.mention(target)])
            == "[@carol:example.org](https://matrix.to/#/@carol:example.org)")
    }

    @Test func multilineDisplayNameIsOneLine() {
        let target = MentionTarget(userId: "@d:example.org", displayName: " Dee\nDee ")
        #expect(target.label == "Dee Dee")
    }

    @Test func parenthesisInUserIdIsPercentEncoded() {
        #expect(MentionMarkdown.permalink(for: "@a(b):example.org")
            == "https://matrix.to/#/@a%28b%29:example.org")
    }

    @Test func bangBeforePillIsEscapedSoItIsNotAnImage() {
        let segments: [ComposerSegment] = [.text("hey!"), .mention(alice)]
        #expect(MentionMarkdown.messageMarkdown(for: segments)
            == "hey\\![Alice](https://matrix.to/#/@alice:example.org)")
    }

    @Test func escapedBangBeforePillIsLeftAlone() {
        let segments: [ComposerSegment] = [.text("hey\\!"), .mention(alice)]
        #expect(MentionMarkdown.messageMarkdown(for: segments)
            == "hey\\![Alice](https://matrix.to/#/@alice:example.org)")
    }

    @Test func oddBackslashBeforePillIsEvened() {
        let segments: [ComposerSegment] = [.text("C:\\"), .mention(alice)]
        #expect(MentionMarkdown.messageMarkdown(for: segments)
            == "C:\\\\[Alice](https://matrix.to/#/@alice:example.org)")
    }

    @Test func draftTextHasNoBoundaryEscapes() {
        let segments: [ComposerSegment] = [.text("hey!"), .mention(alice)]
        #expect(MentionMarkdown.draftText(for: segments)
            == "hey![Alice](https://matrix.to/#/@alice:example.org)")
    }

    @Test func plainTextShowsAtName() {
        let segments: [ComposerSegment] = [.text("ping "), .mention(alice)]
        #expect(MentionMarkdown.plainText(for: segments) == "ping @Alice")
    }

    // MARK: - Mention set

    @Test func twoChipsForSameUserMakeOneMention() {
        let segments: [ComposerSegment] = [.mention(alice), .text(" and "), .mention(bob), .text(" and "), .mention(alice)]
        #expect(MentionMarkdown.mentionedUserIds(in: segments) == ["@alice:example.org", "@bob:example.org"])
        #expect(MentionMarkdown.messageMarkdown(for: segments)
            == "[Alice](https://matrix.to/#/@alice:example.org) and [Bob](https://matrix.to/#/@bob:example.org)"
            + " and [Alice](https://matrix.to/#/@alice:example.org)")
    }

    @Test func noChipMeansNoMentions() {
        #expect(MentionMarkdown.mentionedUserIds(in: [.text("hello @alice")]).isEmpty)
        let outgoing = MentionMarkdown.outgoingMessage(fromDraftText: "hello @alice")
        #expect(outgoing == ComposerOutgoingMessage(markdown: "hello @alice", mentionedUserIds: []))
    }

    @Test func outgoingMessageFromDraftText() {
        let draft = "hey![Alice](https://matrix.to/#/@alice:example.org) see [Bob](https://matrix.to/#/@bob:example.org)"
        let outgoing = MentionMarkdown.outgoingMessage(fromDraftText: draft)
        #expect(outgoing.markdown
            == "hey\\![Alice](https://matrix.to/#/@alice:example.org) see [Bob](https://matrix.to/#/@bob:example.org)")
        #expect(outgoing.mentionedUserIds == ["@alice:example.org", "@bob:example.org"])
    }

    // MARK: - Draft text to chips

    @Test func draftRoundTripKeepsChips() {
        let segments: [ComposerSegment] = [
            .text("hi "),
            .mention(MentionTarget(userId: "@x:example.org", displayName: "*Star* [Bot] \\ & <x>")),
            .text(" and "),
            .mention(alice),
            .mention(alice),
            .text("!"),
        ]
        let draft = MentionMarkdown.draftText(for: segments)
        #expect(MentionMarkdown.segments(fromDraftText: draft) == segments)
    }

    @Test func parsesPercentEncodedUserId() {
        let segments = MentionMarkdown.segments(fromDraftText: "[A](https://matrix.to/#/@a%28b%29:example.org)")
        #expect(segments == [.mention(MentionTarget(userId: "@a(b):example.org", displayName: "A"))])
    }

    @Test func roomAndEventLinksStayText() {
        let text = "[Room](https://matrix.to/#/#room:example.org) [Ev](https://matrix.to/#/!r:example.org/$e)"
        #expect(MentionMarkdown.segments(fromDraftText: text) == [.text(text)])
    }

    @Test func malformedPillsStayText() {
        let inputs = [
            "[Alice](https://matrix.to/#/@alice)",
            "[Alice](https://matrix.to/#/@alice:example.org",
            "[Alice] (https://matrix.to/#/@alice:example.org)",
            "[](https://matrix.to/#/@alice:example.org)",
            "[Al\nice](https://matrix.to/#/@alice:example.org)",
            "[Alice](https://example.org/#/@alice:example.org)",
            "[Alice",
        ]
        for input in inputs {
            #expect(MentionMarkdown.segments(fromDraftText: input) == [.text(input)], "\(input)")
        }
    }

    @Test func textAroundPillIsKept() {
        let segments = MentionMarkdown.segments(fromDraftText: "a [b] [Alice](https://matrix.to/#/@alice:example.org)c")
        #expect(segments == [.text("a [b] "), .mention(alice), .text("c")])
    }

    @Test func emptyDraftHasNoSegments() {
        #expect(MentionMarkdown.segments(fromDraftText: "").isEmpty)
        #expect(MentionMarkdown.draftText(for: []).isEmpty)
    }
}

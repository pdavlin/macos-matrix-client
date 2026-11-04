import Foundation
@testable import Models
import Testing

/// MATRIX-105 (D-6): "@" opens autocomplete over the room members. The
/// trigger, the filter, and the popup selection are pure logic.
struct MentionAutocompleteTests {
    private let members = [
        MentionCandidate(userId: "@alice:example.org", displayName: "Alice Smith", avatarUrl: nil),
        MentionCandidate(userId: "@bob:example.org", displayName: "Bob Jones", avatarUrl: nil),
        MentionCandidate(userId: "@ally:example.org", displayName: "Zed", avatarUrl: nil),
        MentionCandidate(userId: "@slackbot_U123:example.org", displayName: "Renée Smith (Slack)", avatarUrl: nil),
        MentionCandidate(userId: "@nobody:example.org", displayName: nil, avatarUrl: nil),
    ]

    private func ids(_ query: String, excluding: Set<String> = [], limit: Int = 8) -> [String] {
        MentionSuggestionFilter.suggestions(for: query, in: members, excluding: excluding, limit: limit).map(\.userId)
    }

    // MARK: - Filter

    @Test func emptyQueryListsEveryoneByName() {
        #expect(ids("") == [
            "@alice:example.org",
            "@bob:example.org",
            "@nobody:example.org",
            "@slackbot_U123:example.org",
            "@ally:example.org",
        ])
    }

    @Test func nameMatchRanksAboveUserIdMatch() {
        // "Alice Smith" starts with "al"; "@ally" matches by user id only.
        #expect(ids("al") == ["@alice:example.org", "@ally:example.org"])
    }

    @Test func wordPrefixInName() {
        #expect(ids("smi") == ["@alice:example.org", "@slackbot_U123:example.org"])
    }

    @Test func matchIgnoresCaseAndDiacritics() {
        #expect(ids("RENEE") == ["@slackbot_U123:example.org"])
    }

    @Test func userIdMatchWithServer() {
        #expect(ids("bob:exa") == ["@bob:example.org"])
    }

    @Test func memberWithoutNameMatchesByUserId() {
        #expect(ids("nob") == ["@nobody:example.org"])
    }

    @Test func fuzzySubsequenceIsLastTier() {
        // "bjs" is in order in "bob jones" only.
        #expect(ids("bjs") == ["@bob:example.org"])
    }

    @Test func noMatchIsEmpty() {
        #expect(ids("qqq").isEmpty)
    }

    @Test func excludedUsersAreLeftOut() {
        #expect(ids("", excluding: ["@alice:example.org"]).contains("@alice:example.org") == false)
    }

    @Test func limitCapsTheRows() {
        #expect(ids("", limit: 2).count == 2)
    }

    @Test func duplicateMembersShowOnce() {
        let doubled = members + members
        #expect(MentionSuggestionFilter.suggestions(for: "", in: doubled).count == members.count)
    }

    // MARK: - Trigger

    @Test func atAtStartOpensQuery() {
        #expect(MentionTrigger.find(in: "@al", caret: 3) == MentionTrigger(range: NSRange(location: 0, length: 3), query: "al"))
    }

    @Test func bareAtOpensEmptyQuery() {
        #expect(MentionTrigger.find(in: "hi @", caret: 4) == MentionTrigger(range: NSRange(location: 3, length: 1), query: ""))
    }

    @Test func atInEmailDoesNotOpen() {
        #expect(MentionTrigger.find(in: "mail bob@example", caret: 16) == nil)
    }

    @Test func whitespaceEndsQuery() {
        #expect(MentionTrigger.find(in: "@al ", caret: 4) == nil)
    }

    @Test func queryEndsAtCaret() {
        #expect(MentionTrigger.find(in: "@alice", caret: 3)?.query == "al")
    }

    @Test func atAfterChipOpensQuery() {
        let text = "\u{FFFC}@b"
        #expect(MentionTrigger.find(in: text, caret: 3) == MentionTrigger(range: NSRange(location: 1, length: 2), query: "b"))
    }

    @Test func atAfterOpeningParenthesisOpensQuery() {
        #expect(MentionTrigger.find(in: "(@b", caret: 3)?.query == "b")
    }

    @Test func chipEndsQuery() {
        #expect(MentionTrigger.find(in: "@a\u{FFFC}b", caret: 4) == nil)
    }

    @Test func selectionOrInvalidCaretDoesNotOpen() {
        #expect(MentionTrigger.find(in: "@al", caret: nil) == nil)
        #expect(MentionTrigger.find(in: "@al", caret: 0) == nil)
        #expect(MentionTrigger.find(in: "@al", caret: 9) == nil)
    }

    @Test func longQueryCloses() {
        let text = "@" + String(repeating: "a", count: MentionTrigger.maximumQueryLength + 1)
        #expect(MentionTrigger.find(in: text, caret: (text as NSString).length) == nil)
    }

    @Test func emojiBeforeAtUsesUTF16Offsets() {
        let text = "👋 @bo"
        let trigger = MentionTrigger.find(in: text, caret: (text as NSString).length)
        #expect(trigger == MentionTrigger(range: NSRange(location: 3, length: 3), query: "bo"))
    }

    // MARK: - Popup state

    @Test func emptySuggestionsMakeNoState() {
        let trigger = MentionTrigger(range: NSRange(location: 0, length: 1), query: "")
        #expect(MentionAutocompleteState(trigger: trigger, suggestions: []) == nil)
    }

    @Test func selectionWrapsBothWays() throws {
        let trigger = MentionTrigger(range: NSRange(location: 0, length: 1), query: "")
        var state = try #require(MentionAutocompleteState(trigger: trigger, suggestions: Array(members.prefix(3))))
        #expect(state.selected.userId == "@alice:example.org")
        state.moveSelection(by: -1)
        #expect(state.selected.userId == "@ally:example.org")
        state.moveSelection(by: 1)
        state.moveSelection(by: 1)
        #expect(state.selected.userId == "@bob:example.org")
    }

    @Test func candidateTargetUsesDisplayName() {
        #expect(members[0].target == MentionTarget(userId: "@alice:example.org", displayName: "Alice Smith"))
    }
}

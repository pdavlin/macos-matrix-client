@testable import Models
import Testing

/// The text of a reaction chip's tooltip and accessibility label
/// (MATRIX-166).
struct ReactionSenderSummaryTests {
    private static let own = "@me:example.org"
    private static let known = [
        "@ana:example.org": "Ana",
        "@ben:example.org": "Ben",
        "@cy:example.org": "Cy",
        "@di:example.org": "Di",
    ]

    private func summary(_ senderIds: [String]) -> ReactionSenderSummary {
        ReactionSenderSummary(senderIds: senderIds, ownUserId: Self.own) { Self.known[$0] }
    }

    private func extras(_ count: Int) -> [String] {
        (0 ..< count).map { "@extra\($0):example.org" }
    }

    @Test func everyPersonIsNamed() {
        #expect(summary([Self.own]).peopleText == "You")
        #expect(summary(["@ana:example.org"]).peopleText == "Ana")
        #expect(summary(["@ana:example.org", "@ben:example.org"]).peopleText == "Ana and Ben")
        #expect(summary(["@ana:example.org", "@ben:example.org", Self.own]).peopleText == "Ana, Ben and You")
        #expect(
            summary(["@ana:example.org", "@ben:example.org", "@cy:example.org", "@di:example.org", Self.own]).peopleText
                == "Ana, Ben, Cy, Di and You"
        )
    }

    /// MATRIX-259: no "and N others", and "You" keeps its place.
    @Test func sixOrMorePeopleAreAllNamedInTheReactionsOrder() {
        let seven = summary(["@ana:example.org", "@ben:example.org", Self.own, "@cy:example.org", "@di:example.org"] + extras(2))
        #expect(seven.peopleText == "Ana, Ben, You, Cy, Di, extra0 and extra1")
        #expect(seven.names == ["Ana", "Ben", "You", "Cy", "Di", "extra0", "extra1"])
        #expect(seven.peopleCount == 7)
        #expect(seven.tooltip(emojiName: "partyparrot") == ":partyparrot: · Ana, Ben, You, Cy, Di, extra0 and extra1")
        #expect(seven.accessibilityLabel(keyName: "👍") == "👍, 7 reactions: Ana, Ben, You, Cy, Di, extra0 and extra1")
    }

    @Test func aLongListHasNoCap() {
        let fifty = summary(extras(50))
        #expect(fifty.names.count == 50)
        #expect(fifty.peopleText.hasPrefix("extra0, extra1, "))
        #expect(fifty.peopleText.hasSuffix(", extra48 and extra49"))
        #expect(!fifty.peopleText.contains("other"))
    }

    @Test func aUserIdThatOccursTwiceCountsOnceAtItsFirstPlace() {
        let twice = summary(["@ana:example.org", "@ben:example.org", "@ana:example.org", Self.own, Self.own])
        #expect(twice.peopleText == "Ana, Ben and You")
        #expect(twice.peopleCount == 3)

        let repeated = summary([
            "@ana:example.org", "@ben:example.org", "@ana:example.org", Self.own, "@cy:example.org",
            "@ben:example.org", Self.own, "@di:example.org", "@extra0:example.org",
        ])
        #expect(repeated.peopleText == "Ana, Ben, You, Cy, Di and extra0")
        #expect(repeated.peopleCount == 6)
    }

    @Test func aUserWithNoDisplayNameShowsTheLocalpart() {
        #expect(summary(["@slack_u123:bridge.example.org", "@ana:example.org"]).peopleText == "slack_u123 and Ana")
        let blank = ReactionSenderSummary(senderIds: ["@zed:example.org"], ownUserId: Self.own) { _ in "  " }
        #expect(blank.peopleText == "zed")
        #expect(ReactionSenderSummary.localpart(of: "@ana:example.org:8448") == "ana")
        #expect(ReactionSenderSummary.localpart(of: "not a user id") == "not a user id")
        #expect(ReactionSenderSummary.localpart(of: "@") == "@")
    }

    /// MATRIX-259: each person other than the own user gets one lookup,
    /// a repeated user ID too.
    @Test func everyOtherPersonsNameIsLookedUpOnce() {
        var asked: [String] = []
        let senderIds = ["@ana:example.org", Self.own, "@ben:example.org", "@ana:example.org"] + extras(20)
        _ = ReactionSenderSummary(senderIds: senderIds, ownUserId: Self.own) { userId in
            asked.append(userId)
            return nil
        }
        #expect(asked == ["@ana:example.org", "@ben:example.org"] + extras(20))
    }

    @Test func theEmojiNameComesFirstWhenTheCallerHasOne() {
        let two = summary(["@ana:example.org", "@ben:example.org"])
        #expect(two.tooltip(emojiName: "partyparrot") == ":partyparrot: · Ana and Ben")
        #expect(two.tooltip(emojiName: nil) == "Ana and Ben")
        #expect(two.tooltip(emojiName: "") == "Ana and Ben")
        #expect(two.tooltip() == "Ana and Ben")
    }

    @Test func aReactionWithNoSenderHasNoPeople() {
        let none = summary([])
        #expect(none.peopleText.isEmpty)
        #expect(none.tooltip().isEmpty)
        #expect(none.tooltip(emojiName: "partyparrot") == ":partyparrot:")
    }

    @Test func theAccessibilityLabelHasTheSameSentence() {
        let three = summary(["@ana:example.org", "@ben:example.org", Self.own])
        #expect(three.accessibilityLabel(keyName: "👍") == "👍, 3 reactions: Ana, Ben and You")
        #expect(summary([Self.own]).accessibilityLabel(keyName: "partyparrot") == "partyparrot, 1 reaction: You")
    }
}

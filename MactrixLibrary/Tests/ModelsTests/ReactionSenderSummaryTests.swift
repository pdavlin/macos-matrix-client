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

    @Test func oneToFourPeopleAreAllNamed() {
        #expect(summary([Self.own]).peopleText == "You")
        #expect(summary(["@ana:example.org"]).peopleText == "Ana")
        #expect(summary(["@ana:example.org", "@ben:example.org"]).peopleText == "Ana and Ben")
        #expect(summary(["@ana:example.org", "@ben:example.org", Self.own]).peopleText == "Ana, Ben and You")
        #expect(
            summary(["@ana:example.org", "@ben:example.org", "@cy:example.org", "@di:example.org"]).peopleText
                == "Ana, Ben, Cy and Di"
        )
    }

    @Test func moreThanFourPeopleShowThreeNamesAndACount() {
        let seven = summary(["@ana:example.org", "@ben:example.org", Self.own] + extras(4))
        #expect(seven.peopleText == "Ana, Ben, You and 4 others")
        #expect(seven.names.count == ReactionSenderSummary.namesShownWithOthers)
        #expect(seven.otherCount == 4)
        #expect(seven.peopleCount == 7)

        let five = summary(["@ana:example.org", "@ben:example.org", "@cy:example.org", "@di:example.org", "@extra:example.org"])
        #expect(five.peopleText == "Ana, Ben, Cy and 2 others")
    }

    @Test func theOwnUserIsNamedWhenItWouldBeInTheCount() {
        let text = summary(["@ana:example.org", "@ben:example.org", "@cy:example.org", "@di:example.org", Self.own]).peopleText
        #expect(text == "Ana, Ben, You and 2 others")
    }

    @Test func aUserIdThatOccursTwiceCountsOnce() {
        let twice = summary(["@ana:example.org", "@ben:example.org", "@ana:example.org", Self.own, Self.own])
        #expect(twice.peopleText == "Ana, Ben and You")
        #expect(twice.peopleCount == 3)
    }

    @Test func aUserWithNoDisplayNameShowsTheLocalpart() {
        #expect(summary(["@slack_u123:bridge.example.org", "@ana:example.org"]).peopleText == "slack_u123 and Ana")
        let blank = ReactionSenderSummary(senderIds: ["@zed:example.org"], ownUserId: Self.own) { _ in "  " }
        #expect(blank.peopleText == "zed")
        #expect(ReactionSenderSummary.localpart(of: "@ana:example.org:8448") == "ana")
        #expect(ReactionSenderSummary.localpart(of: "not a user id") == "not a user id")
        #expect(ReactionSenderSummary.localpart(of: "@") == "@")
    }

    @Test func namesAreLookedUpOnlyForThePeopleShown() {
        var asked: [String] = []
        let senderIds = ["@ana:example.org", "@ben:example.org", "@cy:example.org"] + extras(20)
        _ = ReactionSenderSummary(senderIds: senderIds, ownUserId: Self.own) { userId in
            asked.append(userId)
            return nil
        }
        #expect(asked == ["@ana:example.org", "@ben:example.org", "@cy:example.org"])
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

import Models
import SwiftUI
import Testing
@testable import UI

/// The card of a reaction chip's long-press menu on iOS (MATRIX-249): the
/// chip's key over the text of the Mac tooltip (MATRIX-166, MATRIX-259).
/// The menu itself is iOS only, so these tests read the card's values.
@MainActor
struct ReactionChipPeopleCardTests {
    private static let ownUserId = "@me:example.org"
    private static let names = ["@ana:example.org": "Ana", "@ben:example.org": "Ben"]

    private struct Sender: ReactionSenderData {
        let senderId: String
        let date = Date(timeIntervalSince1970: 0)
    }

    private struct ChipReaction: Reaction {
        let key: String
        let senders: [Sender]

        var id: String {
            key
        }

        init(key: String, senderIds: [String]) {
            self.key = key
            senders = senderIds.map { Sender(senderId: $0) }
        }
    }

    private func chip(_ reaction: ChipReaction) -> MessageReactionView<ChipReaction> {
        MessageReactionView(
            reaction: reaction,
            active: .constant(true),
            ownUserId: Self.ownUserId,
            displayName: { Self.names[$0] }
        )
    }

    @Test func theCardShowsTheKeyOverEveryPerson() {
        let reaction = ChipReaction(
            key: "👍",
            senderIds: ["@ana:example.org", "@ben:example.org", Self.ownUserId, "@cy:example.org"]
        )
        let card = chip(reaction).peopleCard

        #expect(card.key == "👍")
        #expect(card.text == "Ana, Ben, You and cy")
        #expect(card.text == chip(reaction).toolTipText)
    }

    /// A custom emoji keeps its `mxc://` key, so the card draws its image.
    @Test func aCustomEmojiCardKeepsTheImageKey() {
        let reaction = ChipReaction(key: "mxc://example.org/parrot", senderIds: ["@ana:example.org"])
        let card = chip(reaction).peopleCard

        #expect(card.key == "mxc://example.org/parrot")
        #expect(card.text == "Ana")
    }

    /// The Mac picker keeps the focus in its search field at open. The iOS
    /// sheet does not, so the keyboard does not cover the grid.
    @Test func theMacPickerFocusesItsSearchAtOpen() {
        #expect(ReactionPickerView.focusesSearchAtOpen)
    }
}

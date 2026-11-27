@testable import Models
import Testing

/// The long-press menu of a reaction chip on iOS (MATRIX-249): one action,
/// which does what a tap does.
struct ReactionChipMenuTests {
    @Test func ownReactionOffersRemove() {
        #expect(ReactionChipMenu.toggleTitle(isOwn: true) == "Remove Reaction")
        #expect(ReactionChipMenu.toggleSystemImage(isOwn: true) == "minus.circle")
    }

    @Test func otherReactionOffersAdd() {
        #expect(ReactionChipMenu.toggleTitle(isOwn: false) == "Add Reaction")
        #expect(ReactionChipMenu.toggleSystemImage(isOwn: false) == "plus.circle")
    }
}

import SwiftUI
import Testing
@testable import UI

/// MATRIX-205: the pointer is the pointing hand over the thread pill, the
/// reaction chips, and the rows of the Threads pane.
///
/// SwiftUI has no API to read a view's pointer style, and a hosted view gets
/// no hover in a test. The tests read each view's `Body` type, which names
/// the modifiers the view applies, as `RollingCountTests` does. In that
/// name a modifier applied later comes later in the string.
@MainActor
struct ChipPointerStyleTests {
    private static let pointerStyle = "PointerStyleModifier"
    private static let chipStyle = "ButtonStyleContainerModifier<UI.ReactionChipButtonStyle>"

    private func bodyTypeName<V: View>(of _: V.Type) -> String {
        String(reflecting: V.Body.self)
    }

    /// The index of the first `needle` in `name`, or nil.
    private func offset(of needle: String, in name: String) -> String.Index? {
        name.range(of: needle)?.lowerBound
    }

    /// The chip sets the pointer after its capsule content shape, so the
    /// whole capsule shows the pointing hand.
    @Test
    func reactionChipStyleSetsThePointerOverTheCapsule() throws {
        let name = bodyTypeName(of: ReactionChip<Text>.self)
        let shape = try #require(offset(of: "_ContentShapeModifier<SwiftUI.Capsule>", in: name))
        let pointer = try #require(offset(of: Self.pointerStyle, in: name))
        #expect(shape < pointer)
    }

    @Test
    func reactionToggleUsesTheChipStyle() {
        let name = String(reflecting: MessageReactionToggleStyle.Body.self)
        #expect(name.contains(Self.chipStyle))
    }

    @Test
    func threadPillUsesTheChipStyle() {
        let name = bodyTypeName(of: MessageThreadSummary.self)
        #expect(name.contains(Self.chipStyle))
    }

    /// The row sets the pointer on the button, outside the label, so the
    /// label's full-width content shape shows the pointing hand.
    @Test
    func threadListRowSetsThePointerOnTheButton() throws {
        let name = bodyTypeName(of: ThreadListRow.self)
        let button = try #require(offset(of: "ButtonStyleContainerModifier<SwiftUI.PlainButtonStyle>", in: name))
        let pointer = try #require(offset(of: Self.pointerStyle, in: name))
        #expect(button < pointer)
    }
}

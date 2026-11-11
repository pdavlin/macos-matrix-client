import CoreGraphics
import Models
import Testing
import Tokens
@testable import UI

/// MATRIX-138: where the reaction picker popover hangs from in a row.
struct HoverActionBarGeometryTests {
    private func item(_ action: MessageAction) -> MessageActionItem {
        MessageActionItem(action: action, section: .respond, isEnabled: true)
    }

    private var hoverItems: [MessageActionItem] {
        [
            item(.toggleReaction(key: "👍")),
            item(.toggleReaction(key: "❤️")),
            item(.toggleReaction(key: "😂")),
            item(.openReactionPicker),
            item(.reply),
            item(.replyInThread),
            item(.edit),
            item(.pin),
        ]
    }

    // MARK: - buttonsAfter

    @Test func countsTheButtonsAfterThePicker() {
        #expect(HoverActionBarGeometry.buttonsAfter(.openReactionPicker, in: hoverItems) == 4)
    }

    @Test func theLastButtonHasNoneAfterIt() {
        #expect(HoverActionBarGeometry.buttonsAfter(.pin, in: hoverItems) == 0)
    }

    @Test func aMissingButtonHasNoCount() {
        #expect(HoverActionBarGeometry.buttonsAfter(.unpin, in: hoverItems) == nil)
        #expect(HoverActionBarGeometry.buttonsAfter(.openReactionPicker, in: []) == nil)
    }

    // MARK: - buttonCenterInset

    @Test func theButtonWidthComesFromTheTokens() {
        #expect(HoverActionBarGeometry.buttonWidth == DensityToken.hoverActionButtonSize + 2 * DensityToken.hoverActionButtonPadding)
    }

    @Test func theTrailingButtonCenterIsHalfAButtonInsideTheBar() {
        let expected = DensityToken.hoverActionsTrailingPadding + DensityToken.hoverActionsPadding + HoverActionBarGeometry.buttonWidth / 2
        #expect(HoverActionBarGeometry.buttonCenterInset(buttonsAfter: 0) == expected)
    }

    @Test func eachButtonAfterMovesTheCenterOneButtonWidth() {
        let zero = HoverActionBarGeometry.buttonCenterInset(buttonsAfter: 0)
        #expect(HoverActionBarGeometry.buttonCenterInset(buttonsAfter: 4) == zero + 4 * HoverActionBarGeometry.buttonWidth)
        #expect(HoverActionBarGeometry.buttonCenterInset(buttonsAfter: -1) == zero)
    }

    // MARK: - anchorRect

    private let bounds = CGRect(x: 0, y: 0, width: 600, height: 80)

    @Test func flippedRowAnchorsAtTheTopEdge() throws {
        let rect = try #require(HoverActionBarGeometry.anchorRect(in: bounds, visibleRect: bounds, isFlipped: true, buttonsAfter: 4))
        let centerX = 600 - HoverActionBarGeometry.buttonCenterInset(buttonsAfter: 4)
        #expect(rect.midX == centerX)
        #expect(rect.width == HoverActionBarGeometry.buttonWidth)
        #expect(rect.minY == 0)
        #expect(rect.height == HoverActionBarGeometry.anchorHeight)
    }

    @Test func unflippedRowAnchorsAtMaxY() throws {
        let rect = try #require(HoverActionBarGeometry.anchorRect(in: bounds, visibleRect: bounds, isFlipped: false, buttonsAfter: 4))
        #expect(rect.maxY == 80)
        #expect(rect.height == HoverActionBarGeometry.anchorHeight)
    }

    @Test func noCountAnchorsAtTheTrailingButton() throws {
        let rect = try #require(HoverActionBarGeometry.anchorRect(in: bounds, visibleRect: bounds, isFlipped: true, buttonsAfter: nil))
        #expect(rect.midX == 600 - HoverActionBarGeometry.buttonCenterInset(buttonsAfter: 0))
    }

    @Test func aCutRowAnchorsAtTheTopOfThePartThatShows() throws {
        // A flipped row whose top 30 points are scrolled out of view.
        let visible = CGRect(x: 0, y: 30, width: 600, height: 50)
        let rect = try #require(HoverActionBarGeometry.anchorRect(in: bounds, visibleRect: visible, isFlipped: true, buttonsAfter: 4))
        #expect(rect.minY == 30)

        // The same cut in an unflipped row is at the top, so maxY moves.
        let unflippedVisible = CGRect(x: 0, y: 0, width: 600, height: 50)
        let unflipped = try #require(HoverActionBarGeometry.anchorRect(
            in: bounds,
            visibleRect: unflippedVisible,
            isFlipped: false,
            buttonsAfter: 4
        ))
        #expect(unflipped.maxY == 50)
    }

    @Test func aNarrowRowKeepsTheAnchorInside() throws {
        let narrow = CGRect(x: 0, y: 0, width: 100, height: 80)
        let rect = try #require(HoverActionBarGeometry.anchorRect(in: narrow, visibleRect: narrow, isFlipped: true, buttonsAfter: 8))
        #expect(rect.minX == 0)
        #expect(rect.maxX <= 100)
    }

    @Test func aRowThatDoesNotShowHasNoAnchor() {
        let offscreen = CGRect(x: 0, y: 200, width: 600, height: 50)
        #expect(HoverActionBarGeometry.anchorRect(in: bounds, visibleRect: offscreen, isFlipped: true, buttonsAfter: 4) == nil)
        #expect(HoverActionBarGeometry.anchorRect(in: bounds, visibleRect: .zero, isFlipped: true, buttonsAfter: 4) == nil)
    }

    @Test func theTopEdgeFollowsTheFlip() {
        #expect(HoverActionBarGeometry.topEdge(isFlipped: true) == .minYEdge)
        #expect(HoverActionBarGeometry.topEdge(isFlipped: false) == .maxYEdge)
    }
}

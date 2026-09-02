import Testing
@testable import Tokens

/// Pins the density, accent, and message-bubble values the timeline consumes
/// day one. These are the numbers S-36 removed from the row views; changing a
/// token is an intentional design decision and should be reviewed as one.
@Suite("Appearance tokens")
struct AppearanceTokenTests {
    @Test
    func densityValuesArePinned() {
        #expect(DensityToken.rowVerticalPadding == 4)
        #expect(DensityToken.rowHorizontalPadding == 10)
        #expect(DensityToken.leadingColumnWidth == 64)
        #expect(DensityToken.timestampColumnWidth == 54)
        #expect(DensityToken.profileAvatarSize == 32)
        #expect(DensityToken.hoverActionButtonSize == 24)
        #expect(DensityToken.dividerHeight == 40)
        #expect(DensityToken.threadSummaryPadding == 8)
        #expect(DensityToken.reactionPadding == 4)
        #expect(DensityToken.reactionRowSpacing == 10)
        #expect(DensityToken.receiptAvatarSize == 14)
        #expect(DensityToken.receiptPopoverAvatarSize == 28)
    }

    @Test
    func accentValuesArePinned() {
        #expect(AccentToken.focusBackgroundOpacity == 0.1)
        #expect(AccentToken.hoverBackgroundOpacity == 0.1)
        #expect(AccentToken.inactiveBackgroundOpacity == 0.001)
        #expect(AccentToken.activeBackgroundOpacity == 1)
    }

    @Test
    func bubbleValuesArePinned() {
        #expect(BubbleToken.cornerRadius == 4)
        #expect(BubbleToken.hoverShadowRadius == 4)
        #expect(BubbleToken.hoverShadowOpacity == 0.1)
        #expect(BubbleToken.hoverBorderWidth == 1)
        #expect(BubbleToken.replyBarWidth == 3)
        #expect(BubbleToken.replyBarOpacity == 0.5)
        #expect(BubbleToken.replyBackgroundOpacity == 0.05)
        #expect(BubbleToken.threadSummaryBackgroundOpacity == 0.05)
    }
}

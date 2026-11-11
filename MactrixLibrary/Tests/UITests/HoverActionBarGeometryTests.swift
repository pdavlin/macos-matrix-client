import CoreGraphics
import Models
import Testing
import Tokens
@testable import UI

/// MATRIX-138: where the reaction picker popover hangs from in a row.
/// MATRIX-145: where the timeline's floating hover bar sits.
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

    // MARK: - barSize (MATRIX-145)

    @Test func theBarIsOneButtonWidePerItemPlusTheDividerAndPadding() {
        let size = HoverActionBarGeometry.barSize(for: hoverItems)
        let padding = 2 * DensityToken.hoverActionsPadding
        #expect(size.width == 8 * HoverActionBarGeometry.buttonWidth + HoverActionBarGeometry.dividerWidth + padding)
        #expect(size.height == HoverActionBarGeometry.buttonWidth + padding)
    }

    @Test func aBarWithOneKindOfButtonHasNoDivider() {
        let others = hoverItems.filter { !$0.action.isQuickReaction }
        let reactions = hoverItems.filter(\.action.isQuickReaction)
        let padding = 2 * DensityToken.hoverActionsPadding
        #expect(HoverActionBarGeometry.barSize(for: others).width == 5 * HoverActionBarGeometry.buttonWidth + padding)
        #expect(HoverActionBarGeometry.barSize(for: reactions).width == 3 * HoverActionBarGeometry.buttonWidth + padding)
    }

    // MARK: - bodyTopInset (MATRIX-145)

    @Test func aContinuationRowsBodyStartsBelowTheGap() {
        let grouping = TimelineRowGrouping(isContinuation: true, gap: .sameSenderBurst)
        #expect(HoverActionBarGeometry.bodyTopInset(for: grouping) == RhythmToken.sameSenderBurstGap)
    }

    @Test func aHeaderRowsBodyStartsBelowTheGapAndTheHeader() {
        let grouping = TimelineRowGrouping(isContinuation: false, gap: .pause)
        #expect(HoverActionBarGeometry.bodyTopInset(for: grouping) == RhythmToken.pauseGap + DensityToken.profileAvatarSize)
    }

    // MARK: - barFrame (MATRIX-145)

    private let barSize = CGSize(width: 200, height: 32)
    /// The timeline's visible part: a 600 by 500 window on the document,
    /// with no toolbar over it unless a test says so.
    private let visible = CGRect(x: 0, y: 1000, width: 600, height: 500)

    @Test func theBarHangsFromTheTrailingEdgeAboveTheBodyTop() {
        // An unflipped row in the middle of the visible part.
        let row = CGRect(x: 0, y: 1200, width: 600, height: 60)
        let frame = HoverActionBarGeometry.barFrame(
            barSize: barSize,
            rowRect: row,
            bodyTopInset: 4,
            in: .init(visibleRect: visible, topObscuredHeight: 0, isFlipped: false)
        )
        #expect(frame.size == barSize)
        #expect(frame.maxX == 600 - DensityToken.hoverActionsTrailingPadding)
        // The body top is 4 under the row top (1260); the bar's top rises
        // `riseAboveBody` above it, so its bottom is a little under it.
        #expect(frame.maxY == 1256 + HoverActionBarGeometry.riseAboveBody)
        #expect(frame.minY == 1256 + HoverActionBarGeometry.riseAboveBody - 32)
    }

    @Test func theFlippedBarHasTheSamePlace() {
        // The same row in a flipped space: its top is minY.
        let row = CGRect(x: 0, y: 1200, width: 600, height: 60)
        let frame = HoverActionBarGeometry.barFrame(
            barSize: barSize,
            rowRect: row,
            bodyTopInset: 4,
            in: .init(visibleRect: visible, topObscuredHeight: 0, isFlipped: true)
        )
        #expect(frame.minY == 1204 - HoverActionBarGeometry.riseAboveBody)
        #expect(frame.maxX == 600 - DensityToken.hoverActionsTrailingPadding)
    }

    @Test func aHeaderRowsBarSitsOverItsOwnHeader() {
        let row = CGRect(x: 0, y: 1200, width: 600, height: 80)
        let inset = HoverActionBarGeometry.bodyTopInset(for: TimelineRowGrouping(isContinuation: false, gap: .senderTurn))
        let frame = HoverActionBarGeometry.barFrame(
            barSize: barSize,
            rowRect: row,
            bodyTopInset: inset,
            in: .init(visibleRect: visible, topObscuredHeight: 0, isFlipped: false)
        )
        #expect(frame.maxY <= row.maxY)
        #expect(frame.maxY == row.maxY - inset + HoverActionBarGeometry.riseAboveBody)
    }

    @Test func theTopmostRowTakesTheBarInsideItsTop() {
        // The row's top is 10 under the visible top: the bar above it would
        // be cut, so it moves inside the row's top.
        let row = CGRect(x: 0, y: 1440, width: 600, height: 50)
        let frame = HoverActionBarGeometry.barFrame(
            barSize: barSize,
            rowRect: row,
            bodyTopInset: 0,
            in: .init(visibleRect: visible, topObscuredHeight: 0, isFlipped: false)
        )
        #expect(frame.maxY == row.maxY)
    }

    @Test func theToolbarCountsAsTheTopEdge() {
        // Visible top 1500, a 52-point toolbar: the open top is 1448. The row
        // top (1440) is under it, the bar above the row would not be.
        let row = CGRect(x: 0, y: 1390, width: 600, height: 50)
        let frame = HoverActionBarGeometry.barFrame(
            barSize: barSize,
            rowRect: row,
            bodyTopInset: 0,
            in: .init(visibleRect: visible, topObscuredHeight: 52, isFlipped: false)
        )
        #expect(frame.maxY == row.maxY)
    }

    @Test func aRowWhoseTopIsHiddenTakesTheBarAtTheOpenTop() {
        // The row starts under the toolbar.
        let row = CGRect(x: 0, y: 1420, width: 600, height: 60)
        let frame = HoverActionBarGeometry.barFrame(
            barSize: barSize,
            rowRect: row,
            bodyTopInset: 0,
            in: .init(visibleRect: visible, topObscuredHeight: 52, isFlipped: false)
        )
        #expect(frame.maxY == 1448)
    }

    @Test func theFlippedTopmostRowTakesTheBarInsideItsTop() {
        let flippedVisible = CGRect(x: 0, y: 0, width: 600, height: 500)
        let row = CGRect(x: 0, y: 10, width: 600, height: 50)
        let frame = HoverActionBarGeometry.barFrame(
            barSize: barSize,
            rowRect: row,
            bodyTopInset: 0,
            in: .init(visibleRect: flippedVisible, topObscuredHeight: 0, isFlipped: true)
        )
        #expect(frame.minY == 10)
    }

    @Test func aBarCutByTheBottomEdgeMovesUp() {
        // A header row that barely shows at the bottom.
        let row = CGRect(x: 0, y: 960, width: 600, height: 50)
        let frame = HoverActionBarGeometry.barFrame(
            barSize: barSize,
            rowRect: row,
            bodyTopInset: 40,
            in: .init(visibleRect: visible, topObscuredHeight: 0, isFlipped: false)
        )
        #expect(frame.minY == visible.minY)
    }

    @Test func aNarrowTimelineKeepsTheBarAtItsLeadingEdge() {
        let narrow = CGRect(x: 0, y: 1000, width: 150, height: 500)
        let row = CGRect(x: 0, y: 1200, width: 150, height: 60)
        let frame = HoverActionBarGeometry.barFrame(
            barSize: barSize,
            rowRect: row,
            bodyTopInset: 0,
            in: .init(visibleRect: narrow, topObscuredHeight: 0, isFlipped: false)
        )
        #expect(frame.minX == 0)
    }

    // MARK: - pickerAnchor (MATRIX-145)

    @Test func thePickerAnchorIsThePickerButtonInTheBar() {
        let bar = CGRect(x: 300, y: 1230, width: 236, height: 32)
        let anchor = HoverActionBarGeometry.pickerAnchor(inBar: bar, buttonsAfter: 4)
        #expect(anchor.width == HoverActionBarGeometry.buttonWidth)
        #expect(anchor.minY == bar.minY)
        #expect(anchor.height == bar.height)
        // The same center as the row-based anchor of a row whose trailing
        // edge is the bar's plus the trailing padding.
        let rowMaxX = bar.maxX + DensityToken.hoverActionsTrailingPadding
        #expect(anchor.midX == rowMaxX - HoverActionBarGeometry.buttonCenterInset(buttonsAfter: 4))
    }

    @Test func thePickerAnchorWithoutACountIsTheTrailingButton() {
        let bar = CGRect(x: 300, y: 1230, width: 236, height: 32)
        let anchor = HoverActionBarGeometry.pickerAnchor(inBar: bar, buttonsAfter: nil)
        #expect(anchor.maxX == bar.maxX - DensityToken.hoverActionsPadding)
    }
}

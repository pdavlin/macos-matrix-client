import CoreGraphics
import Models
import Tokens

/// Where the hover action bar and its buttons sit (MATRIX-138, MATRIX-145).
///
/// The Mac timeline controller draws the bar in a hosting view of its own,
/// above all rows (MATRIX-145), and shows the reaction picker as an AppKit
/// popover (MATRIX-138). Neither is inside the SwiftUI row, so the
/// controller computes the places here, from the same tokens the bar lays
/// out with (`HoverActionBar`): the bar hangs from the row's trailing edge,
/// inset by `DensityToken.hoverActionsTrailingPadding`, and every button has
/// the same width.
///
/// Vertically the bar rises `DensityToken.hoverActionsTopOffset` above the
/// top of the message body, as it did when each row drew its own bar. The
/// body starts below the row's rhythm gap and, when the row shows one, its
/// profile header (`bodyTopInset(for:)`).
///
/// The functions take the flip of the coordinate space as an input, so the
/// same math serves the unflipped timeline table and a flipped view.
public enum HoverActionBarGeometry {
    /// The width of one hover button: the button and its padding on both
    /// sides (`HoverButton`).
    public static var buttonWidth: CGFloat {
        DensityToken.hoverActionButtonSize + 2 * DensityToken.hoverActionButtonPadding
    }

    /// The anchor rect's height. A popover needs a rect, not a point.
    static let anchorHeight: CGFloat = 1

    /// The number of hover buttons after `action`, toward the trailing
    /// edge, or nil if the bar does not show `action`.
    ///
    /// - Parameters:
    ///   - action: The button to find, usually `.openReactionPicker`.
    ///   - items: The hover row items in display order, from
    ///     `MessageActionModel.items(for:on: .hoverRow, quickReactionKeys:)`.
    ///     The bar draws the quick reactions, a divider, then the rest; the
    ///     model already orders the reactions first, so the display order is
    ///     the item order.
    public static func buttonsAfter(_ action: MessageAction, in items: [MessageActionItem]) -> Int? {
        guard let index = items.firstIndex(where: { $0.action == action }) else { return nil }
        return items.count - index - 1
    }

    /// The distance from the row's trailing edge to the center of a button
    /// that has `buttonsAfter` buttons on its trailing side.
    public static func buttonCenterInset(buttonsAfter: Int) -> CGFloat {
        DensityToken.hoverActionsTrailingPadding
            + DensityToken.hoverActionsPadding
            + CGFloat(max(buttonsAfter, 0)) * buttonWidth
            + buttonWidth / 2
    }

    /// The rect a popover for a hover button hangs from: one button wide,
    /// centered on the button, at the top edge of the part of the row that
    /// shows.
    ///
    /// - Parameters:
    ///   - bounds: The row view's bounds.
    ///   - visibleRect: The row view's visible rect. A tall row can be cut
    ///     by the scroll view; the anchor then goes to the top of the part
    ///     that shows, so the popover does not point off screen.
    ///   - isFlipped: Whether the row view is flipped. In a flipped view the
    ///     top edge is `minY`, else `maxY`.
    ///   - buttonsAfter: The buttons after the target button (see
    ///     `buttonsAfter(_:in:)`). Nil anchors at the bar's trailing button.
    /// - Returns: The rect in the row view's coordinates, or nil when no part
    ///   of the row shows.
    public static func anchorRect(
        in bounds: CGRect,
        visibleRect: CGRect,
        isFlipped: Bool,
        buttonsAfter: Int?
    ) -> CGRect? {
        let shown = bounds.intersection(visibleRect)
        guard !shown.isNull, shown.width > 0, shown.height > 0 else { return nil }

        let width = min(buttonWidth, shown.width)
        let centerX = bounds.maxX - buttonCenterInset(buttonsAfter: buttonsAfter ?? 0)
        let minX = min(max(centerX - width / 2, shown.minX), shown.maxX - width)

        let height = min(anchorHeight, shown.height)
        let minY = isFlipped ? shown.minY : shown.maxY - height
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    /// The popover edge that opens above the anchor: the top edge of the
    /// rect in the row view's coordinates.
    public static func topEdge(isFlipped: Bool) -> CGRectEdge {
        isFlipped ? .minYEdge : .maxYEdge
    }

    // MARK: - The floating bar (MATRIX-145)

    /// How far the bar's top rises above the top of the message body.
    public static var riseAboveBody: CGFloat {
        -DensityToken.hoverActionsTopOffset
    }

    /// The clear margin the floating host keeps on each side of the bar. The
    /// bar's shadow and its reveal slide (`MotionToken.revealOffset` down)
    /// draw inside it, so the host never cuts them. The host takes no clicks
    /// in the margin.
    public static var hostMargin: CGFloat {
        BubbleToken.hoverShadowRadius + MotionToken.revealOffset
    }

    /// The width of the divider between the quick reactions and the other
    /// buttons: one hairline (`Divider` in an `HStack`).
    static let dividerWidth: CGFloat = 1

    /// The bar's size for `items`, without the host margin: one button width
    /// for each item, the divider when the bar has both quick reactions and
    /// other buttons, and the bar's padding. A test checks it against the
    /// laid-out view.
    ///
    /// - Parameter items: The hover row items.
    public static func barSize(for items: [MessageActionItem]) -> CGSize {
        let reactionCount = items.count(where: \.action.isQuickReaction)
        let hasDivider = reactionCount > 0 && reactionCount < items.count
        let width = CGFloat(items.count) * buttonWidth
            + (hasDivider ? dividerWidth : 0)
            + 2 * DensityToken.hoverActionsPadding
        return CGSize(width: width, height: buttonWidth + 2 * DensityToken.hoverActionsPadding)
    }

    /// How far the message body starts below the top of its row.
    ///
    /// `MessageRunRow` puts the rhythm gap above the row, then the profile
    /// header when the row shows one, then the body. The header is as tall
    /// as its avatar: the bold name is shorter than
    /// `DensityToken.profileAvatarSize` at every font size the appearance
    /// settings allow (a test checks this).
    ///
    /// - Parameter grouping: The row's place in its run.
    public static func bodyTopInset(for grouping: TimelineRowGrouping) -> CGFloat {
        grouping.gap.spacing + (grouping.showsProfileHeader ? DensityToken.profileAvatarSize : 0)
    }

    /// The part of the timeline that shows, as the floating bar's placement
    /// reads it.
    public struct Viewport: Equatable, Sendable {
        /// The part of the timeline that shows, in the coordinates of the
        /// row rects.
        public let visibleRect: CGRect
        /// The height at the top of `visibleRect` that the toolbar covers.
        /// The timeline runs under the toolbar.
        public let topObscuredHeight: CGFloat
        /// Whether the coordinate space is flipped. In a flipped space the
        /// top edge is `minY`, else `maxY`.
        public let isFlipped: Bool

        public init(visibleRect: CGRect, topObscuredHeight: CGFloat, isFlipped: Bool) {
            self.visibleRect = visibleRect
            self.topObscuredHeight = topObscuredHeight
            self.isFlipped = isFlipped
        }
    }

    /// The frame of the floating bar for one row.
    ///
    /// The bar's trailing edge is `DensityToken.hoverActionsTrailingPadding`
    /// inside the row's trailing edge, and its top is `riseAboveBody` above
    /// the body's top, the place the bar had inside the row. The bar stays
    /// inside the part of the timeline that shows:
    /// - If its top would be under the top edge or the toolbar, the bar moves
    ///   inside the row's top. If the row's top is hidden too, the bar's top
    ///   goes to the top of the part that shows.
    /// - If its bottom would be under the bottom edge, the bar moves up.
    /// - A bar wider than the part that shows starts at its leading edge.
    ///
    /// - Parameters:
    ///   - barSize: The bar's size, without the host margin.
    ///   - rowRect: The row's cell rect.
    ///   - bodyTopInset: See `bodyTopInset(for:)`.
    ///   - viewport: The part of the timeline that shows.
    /// - Returns: The bar's frame in the coordinates of `rowRect`.
    public static func barFrame(
        barSize: CGSize,
        rowRect: CGRect,
        bodyTopInset: CGFloat,
        in viewport: Viewport
    ) -> CGRect {
        let visibleRect = viewport.visibleRect
        let topObscuredHeight = viewport.topObscuredHeight
        let isFlipped = viewport.isFlipped
        // `down` is the sign of a move toward the bottom of the screen.
        let down: CGFloat = isFlipped ? 1 : -1
        let isAbove = { (first: CGFloat, second: CGFloat) in (first - second) * down < 0 }
        let isBelow = { (first: CGFloat, second: CGFloat) in (first - second) * down > 0 }

        let rowTop = isFlipped ? rowRect.minY : rowRect.maxY
        let visibleTop = (isFlipped ? visibleRect.minY : visibleRect.maxY) + down * max(topObscuredHeight, 0)
        let visibleBottom = isFlipped ? visibleRect.maxY : visibleRect.minY

        let bodyTop = rowTop + down * bodyTopInset
        var barTop = bodyTop - down * riseAboveBody
        if isAbove(barTop, visibleTop) {
            barTop = isAbove(rowTop, visibleTop) ? visibleTop : rowTop
        }
        if isBelow(barTop + down * barSize.height, visibleBottom) {
            barTop = visibleBottom - down * barSize.height
            if isAbove(barTop, visibleTop) {
                barTop = visibleTop
            }
        }

        let minY = isFlipped ? barTop : barTop - barSize.height
        let minX = max(rowRect.maxX - DensityToken.hoverActionsTrailingPadding - barSize.width, visibleRect.minX)
        return CGRect(x: minX, y: minY, width: barSize.width, height: barSize.height)
    }

    /// The rect the reaction picker popover hangs from when the floating bar
    /// shows for the message: the picker button's rect in the bar.
    ///
    /// - Parameters:
    ///   - barRect: The bar's frame, from `barFrame(...)`.
    ///   - buttonsAfter: The buttons after the picker button (see
    ///     `buttonsAfter(_:in:)`). Nil anchors at the bar's trailing button.
    /// - Returns: The button's rect, in the coordinates of `barRect`.
    public static func pickerAnchor(inBar barRect: CGRect, buttonsAfter: Int?) -> CGRect {
        let centerX = barRect.maxX
            - DensityToken.hoverActionsPadding
            - CGFloat(max(buttonsAfter ?? 0, 0)) * buttonWidth
            - buttonWidth / 2
        return CGRect(x: centerX - buttonWidth / 2, y: barRect.minY, width: buttonWidth, height: barRect.height)
    }
}

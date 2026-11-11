import CoreGraphics
import Models
import Tokens

/// Where the hover action bar's buttons sit in a message row (MATRIX-138).
///
/// The timeline controller shows the reaction picker as an AppKit popover,
/// outside the SwiftUI row, so it cannot read the button's frame. It
/// computes the picker button's place from the same tokens the bar lays out
/// with (`MessageEventBodyView.hoverActions`): the bar hangs from the row's
/// trailing edge, inset by `DensityToken.hoverActionsTrailingPadding`, and
/// every button has the same width.
///
/// The vertical place is the top of the row. The bar floats a little above
/// the message body, and the body sits below the profile header when the row
/// shows one, so the row top is the nearest place that does not depend on
/// the row content. The old SwiftUI popover anchored at the row top too.
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
}

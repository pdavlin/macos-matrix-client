import SwiftUI

/// Vertical and horizontal spacing tokens for the timeline rows.
///
/// The row chrome (timestamp column, profile header, hover actions, reactions,
/// dividers, read receipts) sizes itself from these values.
public enum DensityToken {
    /// Vertical padding inside a message row.
    public static let rowVerticalPadding: CGFloat = 4

    /// Horizontal padding at the row edges.
    public static let rowHorizontalPadding: CGFloat = 10

    /// Width of the leading column holding the timestamp and avatar.
    public static let leadingColumnWidth: CGFloat = 64

    /// Width of the timestamp area within the leading column.
    public static let timestampColumnWidth: CGFloat = 54

    /// Trailing padding of the timestamp.
    public static let timestampTrailingPadding: CGFloat = 5

    /// Top padding of the timestamp.
    public static let timestampTopPadding: CGFloat = 3

    /// Avatar size in the profile header.
    public static let profileAvatarSize: CGFloat = 32

    /// Size of hover action buttons.
    public static let hoverActionButtonSize: CGFloat = 24

    /// Padding inside hover action buttons.
    public static let hoverActionButtonPadding: CGFloat = 2

    /// Padding around the hover action bar itself.
    public static let hoverActionsPadding: CGFloat = 2

    /// Trailing padding of the hover action bar.
    public static let hoverActionsTrailingPadding: CGFloat = 20

    /// Vertical offset that floats the hover action bar over the row.
    public static let hoverActionsTopOffset: CGFloat = -30

    /// Height of the separator inside the hover action bar.
    public static let hoverActionsDividerHeight: CGFloat = 18

    /// Padding around a reaction pill.
    public static let reactionPadding: CGFloat = 4

    /// Padding between a reaction key and its count.
    public static let reactionCountPadding: CGFloat = 6

    /// Spacing between the message body and the reaction/read-receipts row.
    public static let reactionRowSpacing: CGFloat = 10

    /// Padding inside the thread summary button.
    public static let threadSummaryPadding: CGFloat = 8

    /// Height of virtual-item dividers (date divider, read marker, start).
    public static let dividerHeight: CGFloat = 40

    /// Horizontal padding of virtual-item dividers.
    public static let dividerHorizontalPadding: CGFloat = 10

    /// Avatar size in the read-receipts row.
    public static let receiptAvatarSize: CGFloat = 14

    /// Avatar size in the read-receipts popover.
    public static let receiptPopoverAvatarSize: CGFloat = 28

    /// Stroke width separating overlapping read-receipt avatars.
    public static let receiptAvatarStrokeWidth: CGFloat = 3

    /// Inner padding of the scroll-to-bottom chip.
    public static let scrollChipPadding: CGFloat = 8

    /// Spacing between the unread count and the chevron inside the chip.
    public static let scrollChipSpacing: CGFloat = 4

    /// Margin between the scroll-to-bottom chip and the timeline edge.
    public static let scrollChipMargin: CGFloat = 12

    /// Spacing between the icon, text, and actions of the send-failure row.
    public static let sendFailureSpacing: CGFloat = 6

    /// Padding above the send-failure row, separating it from the message body.
    public static let sendFailureTopPadding: CGFloat = 4
}

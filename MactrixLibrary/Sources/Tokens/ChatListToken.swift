import SwiftUI

/// Size, type, and opacity tokens for the sidebar chat list (MATRIX-67).
///
/// The values follow a static teardown of Beeper Desktop 4.3.229's inbox: a
/// grid of pinned favourites above one recency-ordered list of two-line rows.
/// Beeper sets its type in `system-ui`, which is SF Pro on macOS, so the row
/// views use the system font at these sizes.
public enum ChatListToken {
    // MARK: Row

    /// Vertical padding inside a chat-list row (Beeper: `padding: 10px 8px`).
    public static let rowVerticalPadding: CGFloat = 10

    /// Horizontal padding inside a chat-list row.
    public static let rowHorizontalPadding: CGFloat = 8

    /// Width of the leading column that holds the unread or error dot.
    public static let indicatorColumnWidth: CGFloat = 12

    /// Diameter of the unread dot and the send-failure dot.
    public static let indicatorDotSize: CGFloat = 6

    /// Avatar diameter in a chat-list row.
    public static let avatarSize: CGFloat = 46

    /// Spacing between the avatar and the text column.
    public static let avatarTextSpacing: CGFloat = 10

    /// Spacing between the title line and the preview.
    public static let lineSpacing: CGFloat = 2

    // MARK: Network badge

    /// Side of the network badge drawn over the avatar's bottom-right corner.
    public static let networkBadgeSize: CGFloat = 16

    /// Offset of the network badge past the avatar's bottom-right edge
    /// (Beeper: `bottom: -2px; right: -2px`).
    public static let networkBadgeOffset: CGFloat = -2

    /// Corner radius of the badge squircle, as a fraction of its side.
    public static let networkBadgeCornerRadiusRatio: CGFloat = 0.35

    // MARK: Type

    /// Room title size.
    public static let titleFontSize: CGFloat = 14

    /// Room title weight when the room has unread messages.
    public static let titleUnreadWeight: Font.Weight = .semibold

    /// Room title weight when the room is read.
    public static let titleReadWeight: Font.Weight = .medium

    /// Timestamp size.
    public static let timestampFontSize: CGFloat = 11

    /// Opacity of the timestamp against the primary color.
    public static let timestampOpacity: Double = 0.7

    /// Preview size.
    public static let previewFontSize: CGFloat = 13

    /// Lines of preview text before truncation.
    public static let previewLineLimit: Int = 2

    /// Opacity of the preview against the primary color.
    public static let previewOpacity: Double = 0.7

    // MARK: Unread count

    /// Unread-count size, set bold.
    public static let unreadCountFontSize: CGFloat = 10

    /// Minimum width of the unread-count capsule, so one digit reads as a
    /// circle.
    public static let unreadCountMinWidth: CGFloat = 14

    /// Horizontal padding inside the unread-count capsule.
    public static let unreadCountHorizontalPadding: CGFloat = 4

    /// Opacity of the primary color that fills a muted room's capsule.
    public static let mutedCountOpacity: Double = 0.3

    /// Size of the accent "@" drawn before the count when the room mentions
    /// the user, set bold.
    public static let mentionGlyphFontSize: CGFloat = 12

    /// Opacity of white behind the count on a selected (accent-filled) row,
    /// where an accent capsule would vanish.
    public static let selectedRowCountOpacity: Double = 0.3

    // MARK: Pinned favourites

    /// Avatar diameter in a pinned tile.
    public static let pinnedAvatarSize: CGFloat = 52

    /// Minimum width of a pinned tile; the grid fits as many as the sidebar
    /// width allows.
    public static let pinnedTileMinWidth: CGFloat = 80

    /// Top padding inside a pinned tile (Beeper: `padding: 12px 12px 10px`).
    public static let pinnedTileTopPadding: CGFloat = 12

    /// Horizontal padding inside a pinned tile.
    public static let pinnedTileHorizontalPadding: CGFloat = 12

    /// Bottom padding inside a pinned tile.
    public static let pinnedTileBottomPadding: CGFloat = 10

    /// Spacing between the pinned avatar and its title.
    public static let pinnedTitleSpacing: CGFloat = 6

    /// Diameter of the unread dot on a pinned avatar with no count.
    public static let pinnedUnreadDotSize: CGFloat = 12

    /// How far the pinned unread mark sits past the avatar's top-right corner.
    public static let pinnedUnreadOffset: CGFloat = 4

    /// Pinned title size, set semibold.
    public static let pinnedTitleFontSize: CGFloat = 12

    /// Corner radius of a pinned tile's selected background.
    public static let pinnedSelectedCornerRadius: CGFloat = 8

    /// Opacity of the primary color behind the selected pinned tile.
    public static let pinnedSelectedOpacity: Double = 0.1
}

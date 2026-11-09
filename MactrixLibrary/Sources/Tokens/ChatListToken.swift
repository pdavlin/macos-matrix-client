import SwiftUI

/// Size, type, and opacity tokens for the sidebar chat list (MATRIX-67).
///
/// The values started from a static teardown of Beeper Desktop 4.3.229's
/// inbox: a grid of pinned favourites above one recency-ordered list of rows.
/// Beeper sets its type in `system-ui`, which is SF Pro on macOS, so the row
/// views use the system font at these sizes.
///
/// MATRIX-129 made the list denser than Beeper's, as the only layout (no
/// toggle): a 36 pt avatar, one preview line, and smaller type and padding.
public enum ChatListToken {
    // MARK: Row

    /// Vertical padding inside a chat-list row.
    ///
    /// MATRIX-129: 6 pt (Beeper's `padding: 10px 8px` gave 10), for the
    /// denser list.
    public static let rowVerticalPadding: CGFloat = 6

    /// Horizontal padding inside a chat-list row (MATRIX-123).
    ///
    /// Zero, because the macOS sidebar `List` already insets every row by
    /// 16 pt on each side and ignores `listRowInsets`. With this value the
    /// avatar starts 16 pt from the chat list's leading edge (it was 36 pt).
    public static let rowHorizontalPadding: CGFloat = 0

    /// Diameter of the unread dot and the send-failure dot.
    ///
    /// MATRIX-123: the dot sits on the avatar's top-leading corner, not in a
    /// column of its own, so the avatar can start at the row's leading edge
    /// and an unread change never moves the row's content.
    public static let indicatorDotSize: CGFloat = 8

    /// Avatar diameter in a chat-list row.
    ///
    /// MATRIX-129: 36 pt (was Beeper's 46). Below
    /// `clusterFullModeMinimumSize`, so a row's cluster draws three bubbles.
    public static let avatarSize: CGFloat = 36

    /// Spacing between the avatar and the text column.
    ///
    /// MATRIX-129: 8 pt (was 10), to match the smaller avatar.
    public static let avatarTextSpacing: CGFloat = 8

    /// Spacing between the title line and the preview.
    public static let lineSpacing: CGFloat = 2

    // MARK: Network badge

    /// Side of the network badge as a fraction of the avatar's diameter
    /// (MATRIX-129).
    ///
    /// The badge was a fixed 16 pt, sized for a 46 pt avatar. It now scales
    /// with the avatar: 13.5 pt on a 36 pt row, 16.5 pt on a 44 pt pinned
    /// tile.
    public static let networkBadgeSizeRatio: CGFloat = 0.375

    /// Side of the network badge for an avatar of the given diameter.
    ///
    /// - Parameter avatarSize: the avatar's diameter in points.
    /// - Returns: `avatarSize * networkBadgeSizeRatio`.
    public static func networkBadgeSize(forAvatarSize avatarSize: CGFloat) -> CGFloat {
        avatarSize * networkBadgeSizeRatio
    }

    /// Offset of the network badge past the avatar's bottom-right edge
    /// (Beeper: `bottom: -2px; right: -2px`).
    public static let networkBadgeOffset: CGFloat = -2

    /// Corner radius of the badge squircle, as a fraction of its side.
    public static let networkBadgeCornerRadiusRatio: CGFloat = 0.35

    // MARK: Type

    /// Room title size.
    ///
    /// MATRIX-129: 13 pt (was 14), for the denser list.
    public static let titleFontSize: CGFloat = 13

    /// Room title weight when the room has unread messages.
    public static let titleUnreadWeight: Font.Weight = .semibold

    /// Room title weight when the room is read.
    public static let titleReadWeight: Font.Weight = .medium

    /// Layout priority of the room title against the timestamp (MATRIX-123).
    ///
    /// Above the default 0, so the title takes all the width the timestamp
    /// does not need. Without it the title line's `HStack` splits the free
    /// width between the title and its spacer, and a name truncates after
    /// about six characters.
    public static let titleLayoutPriority: Double = 1

    /// Timestamp size: smaller than the title, so the time reads as metadata.
    public static let timestampFontSize: CGFloat = 11

    /// Timestamp weight. Regular whatever the unread state, so only the
    /// title carries the unread emphasis.
    public static let timestampWeight: Font.Weight = .regular

    /// Timestamp color (MATRIX-123): the system secondary color, as in
    /// Beeper's inbox.
    public static var timestampStyle: HierarchicalShapeStyle {
        .secondary
    }

    /// Preview size.
    ///
    /// MATRIX-129: 12 pt (was 13), one point under the title.
    public static let previewFontSize: CGFloat = 12

    /// Lines of preview text before truncation.
    ///
    /// MATRIX-129: one line (was two), so every row is one title line and one
    /// preview line.
    public static let previewLineLimit: Int = 1

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
    ///
    /// MATRIX-129: 44 pt (was 52). Exactly `clusterFullModeMinimumSize`, so a
    /// pinned group's cluster draws five bubbles and the "+N" label.
    public static let pinnedAvatarSize: CGFloat = 44

    /// Minimum width of a pinned tile; the grid fits as many as the sidebar
    /// width allows.
    public static let pinnedTileMinWidth: CGFloat = 80

    /// Top padding inside a pinned tile (Beeper: `padding: 12px 12px 10px`).
    ///
    /// MATRIX-123: 8 pt, not Beeper's 12 pt, to remove the gap above the
    /// pinned row. It still holds the unread mark, which sits
    /// `pinnedUnreadOffset` above the avatar.
    public static let pinnedTileTopPadding: CGFloat = 8

    /// Horizontal padding inside a pinned tile.
    ///
    /// MATRIX-129: 10 pt (was 12), for the denser grid.
    public static let pinnedTileHorizontalPadding: CGFloat = 10

    /// Bottom padding inside a pinned tile.
    ///
    /// MATRIX-129: 6 pt (was 10), for the denser grid.
    public static let pinnedTileBottomPadding: CGFloat = 6

    /// Spacing between the pinned avatar and its title.
    ///
    /// MATRIX-129: 4 pt (was 6).
    public static let pinnedTitleSpacing: CGFloat = 4

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

    // MARK: Avatar initials

    /// Initials size as a fraction of the circle's diameter, for one letter.
    public static let initialsSingleFontRatio: CGFloat = 0.4

    /// Initials size as a fraction of the circle's diameter, for two letters
    /// (MATRIX-129), so both fit inside the circle.
    public static let initialsDoubleFontRatio: CGFloat = 0.36

    // MARK: Bubble cluster (MATRIX-129)

    /// One bubble of a group avatar's cluster.
    ///
    /// Each bubble is a circle the size of the whole avatar, scaled by
    /// `scale` around its center and then moved from the avatar's center by
    /// `offsetX` and `offsetY` times the avatar's side. This is CSS
    /// `translate(x%, y%) scale(s)` on a full-size element: the translate is
    /// relative to the element's own unscaled size.
    public struct ClusterSlot: Equatable, Sendable {
        /// The bubble's diameter as a fraction of the avatar's side.
        public let scale: CGFloat
        /// Horizontal offset of the bubble's center, as a fraction of the
        /// avatar's side. Positive moves right.
        public let offsetX: CGFloat
        /// Vertical offset of the bubble's center, as a fraction of the
        /// avatar's side. Positive moves down.
        public let offsetY: CGFloat

        public init(scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
            self.scale = scale
            self.offsetX = offsetX
            self.offsetY = offsetY
        }
    }

    /// The cluster's bubbles in fill order: the first hero takes the largest
    /// bubble at the top left, and each next hero a smaller one. In full mode
    /// the fifth slot can hold the "+N" label instead of a face.
    public static let clusterSlots: [ClusterSlot] = [
        ClusterSlot(scale: 0.48, offsetX: -0.14, offsetY: -0.135),
        ClusterSlot(scale: 0.35, offsetX: 0.26, offsetY: 0.08),
        ClusterSlot(scale: 0.27, offsetX: -0.06, offsetY: 0.28),
        ClusterSlot(scale: 0.215, offsetX: 0.25, offsetY: -0.24),
        ClusterSlot(scale: 0.20, offsetX: -0.33, offsetY: 0.20),
    ]

    /// Smallest avatar side that draws the full cluster: five bubbles and
    /// the "+N" label. A smaller avatar draws at most three bubbles and no
    /// label, because a fourth and fifth bubble would be specks.
    public static let clusterFullModeMinimumSize: CGFloat = 44

    /// Size of the "+N" label as a fraction of the avatar's side. Larger than
    /// its slot's bubble, so the text stays legible; the label has no fill.
    public static let clusterOverflowFontRatio: CGFloat = 0.17
}

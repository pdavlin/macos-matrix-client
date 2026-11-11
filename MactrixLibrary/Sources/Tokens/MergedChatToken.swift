import CoreGraphics

/// Layout values for merged chats in the chat list and the Merge Chats sheet
/// (MATRIX-141).
public enum MergedChatToken {
    // MARK: Badges

    /// How far each further network badge moves toward the leading edge,
    /// as a fraction of the badge's side. Below 1, so the badges overlap and
    /// the stack stays near the avatar's corner.
    public static let badgeStepRatio: CGFloat = 0.6

    // MARK: Sheet

    /// Width of the Merge Chats sheet.
    public static let sheetWidth: CGFloat = 420

    /// Avatar diameter in the sheet's member rows.
    public static let sheetMemberAvatarSize: CGFloat = 28

    /// Avatar diameter in the sheet's avatar picker.
    public static let sheetPickerAvatarSize: CGFloat = 36

    /// Width of the ring around the chosen avatar in the picker.
    public static let sheetPickerRingWidth: CGFloat = 2

    /// Gap between the chosen avatar and its ring.
    public static let sheetPickerRingInset: CGFloat = 3

    // MARK: Detail placeholder (Phase B)

    /// Avatar diameter of the merged chat in the detail placeholder. The
    /// chat-list row avatar is 36 (`ChatListToken.avatarSize`); the
    /// placeholder avatar is a heading.
    public static let placeholderAvatarSize: CGFloat = 64

    /// Avatar diameter of each member chat in the detail placeholder. Large
    /// enough for the network badge to read.
    public static let placeholderMemberAvatarSize: CGFloat = 32

    /// Widest the placeholder's member list grows in a wide window.
    public static let placeholderMaxWidth: CGFloat = 360
}

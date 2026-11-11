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
}

import Foundation

/// The long-press menu of a reaction chip on iOS (MATRIX-249).
///
/// A tap on a chip toggles the account's own reaction with the chip's key.
/// A long press shows the people who posted the reaction, in the words of
/// the Mac tooltip (`ReactionSenderSummary.tooltip(emojiName:)`,
/// MATRIX-166 and MATRIX-259), with one action that does what a tap does.
/// The Mac has no such menu: its chip shows the people in a tooltip.
///
/// Usage:
/// ```swift
/// Button(ReactionChipMenu.toggleTitle(isOwn: isOwn), systemImage: ReactionChipMenu.toggleSystemImage(isOwn: isOwn)) {
///     toggle()
/// }
/// ```
public enum ReactionChipMenu {
    /// The title of the menu's action: "Remove Reaction" when the account
    /// posted the reaction, else "Add Reaction".
    public static func toggleTitle(isOwn: Bool) -> String {
        isOwn
            ? String(localized: "Remove Reaction", comment: "Reaction chip menu: removes the account's own reaction.")
            : String(localized: "Add Reaction", comment: "Reaction chip menu: adds the same reaction from the account.")
    }

    /// The SF Symbol of the menu's action.
    public static func toggleSystemImage(isOwn: Bool) -> String {
        isOwn ? "minus.circle" : "plus.circle"
    }
}

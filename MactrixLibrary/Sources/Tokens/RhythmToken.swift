import SwiftUI

/// Conversation-rhythm spacing: the gap above a message row, by band
/// (MATRIX-68).
///
/// The values are Beeper's. They are added *on top of* the row's own
/// `DensityToken.rowVerticalPadding`, outside the hover/focus background,
/// rather than replacing it: that padding is the inset of the row's highlight,
/// which plays the part Beeper's bubble padding plays, and Beeper's gaps sit
/// between bubbles. No existing token value changes.
///
/// The band itself is decided in `Models.TimelineGapBand`; these are only the
/// points each band is worth.
public enum RhythmToken {
    /// No rhythm gap: after a non-message row, or across a day change where a
    /// date divider already separates the two messages.
    public static let noGap: CGFloat = 0

    /// Same sender, within a minute.
    public static let sameSenderBurstGap: CGFloat = 2

    /// Another sender, within a minute.
    public static let senderTurnGap: CGFloat = 4

    /// More than a minute apart.
    public static let shortPauseGap: CGFloat = 4

    /// More than five minutes apart.
    public static let pauseGap: CGFloat = 13

    /// More than four hours apart.
    public static let longPauseGap: CGFloat = 26
}

import SwiftUI

/// Size and timing tokens for the timeline chrome of MATRIX-136: the
/// jump-to-message flash, the "New" divider, and the day pills.
///
/// The motion values that other stories share (flash length and peak, the
/// divider glow and dim) live in `MotionToken`. This file holds only the
/// values that belong to this chrome.
public enum TimelineChromeToken {
    // MARK: Jump-to-message flash

    /// Where the flash reaches its peak, as a fraction of
    /// `MotionToken.jumpFlashDuration`.
    public static let jumpFlashPeakFraction: Double = 0.2

    // MARK: "New" divider

    /// Font size of the "New" label. Close to the body size the old "Read
    /// Marker" label used; the small caps make it read smaller.
    public static let newDividerFontSize: CGFloat = 13

    /// Thickness of the accent lines on both sides of the label.
    public static let newDividerLineThickness: CGFloat = 1

    /// Radius of the accent glow when the divider first appears.
    public static let newDividerGlowRadius: CGFloat = 4

    // MARK: Day pill

    /// Font size of the date in a day pill.
    public static let dayPillFontSize: CGFloat = 12

    /// Vertical padding inside a day pill.
    public static let dayPillVerticalPadding: CGFloat = 4

    /// Horizontal padding inside a day pill.
    public static let dayPillHorizontalPadding: CGFloat = 10

    /// Opacity of the black shadow under a day pill.
    public static let dayPillShadowOpacity: Double = 0.08

    /// Blur radius of the shadow under a day pill.
    public static let dayPillShadowRadius: CGFloat = 2

    /// Vertical offset of the shadow under a day pill.
    public static let dayPillShadowOffsetY: CGFloat = 1

    /// Thickness of the separator line behind the pill in a date divider row.
    public static let dayDividerLineThickness: CGFloat = 1

    // MARK: Sticky day pill

    /// Distance from the top of the visible timeline to the sticky pill.
    public static let stickyDayPillTopInset: CGFloat = 8

    /// Space around the sticky pill inside its host, so the shadow is not
    /// clipped.
    public static let stickyDayPillShadowMargin: CGFloat = 4

    /// Height of the band at the top of the visible timeline that the sticky
    /// pill covers. A date divider row inside this band hides the sticky pill,
    /// so two pills never show at the same time.
    public static let stickyDayPillEdgeBand: CGFloat = 40

    /// How long the sticky pill stays after scrolling stops.
    public static let stickyDayPillIdleDelay: Double = 1

    /// Fade-out length of the sticky pill.
    public static let stickyDayPillFadeOutDuration: Double = 0.25
}

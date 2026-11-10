import SwiftUI

/// Motion tokens (visual flair batch, 2026-11-09). One easing curve for almost
/// all motion, a few durations, and one spring for small pops. The values take
/// their shape from Slack's and Beeper's motion systems; no asset is copied.
///
/// Rules:
/// - Motion in the timeline never changes a row's height. Animate opacity,
///   color, a layer transform, or an overlay only (MATRIX-49 and 50).
/// - Every animation goes through `animation(_:reduceMotion:)`, so Reduce
///   Motion turns it into an instant change.
public enum MotionToken {
    /// Hover color and opacity changes.
    public static let hoverDuration: Double = 0.08

    /// State changes: selection, press release, count changes.
    public static let stateDuration: Double = 0.16

    /// The hover action bar fades and slides into place.
    public static let revealDuration: Double = 0.15

    /// How far the hover action bar slides as it appears, in points.
    public static let revealOffset: CGFloat = 8

    /// The scale of a pressed chip or button.
    public static let pressedScale: CGFloat = 0.94

    /// The jump-to-message highlight: total length and peak opacity.
    public static let jumpFlashDuration: Double = 1.5
    public static let jumpFlashPeakOpacity: Double = 0.25

    /// The "New" divider: glow length, then the delay before it dims, and the
    /// opacity it dims to.
    public static let newDividerGlowDuration: Double = 0.6
    public static let newDividerDimDelay: Double = 3
    public static let newDividerDimmedOpacity: Double = 0.5

    /// The house curve. Use it for almost every state change.
    public static func standard(duration: Double = stateDuration) -> Animation {
        .timingCurve(0.36, 0.19, 0.29, 1, duration: duration)
    }

    /// A short spring with a little overshoot, for pops.
    public static let pop: Animation = .spring(response: 0.3, dampingFraction: 0.62)

    /// The animation to use, or nil when Reduce Motion is on.
    public static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

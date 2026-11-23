import SwiftUI

/// Motion tokens (visual flair batch, 2026-11-09). One easing curve for almost
/// all motion, a few durations, and one spring for small pops. The values take
/// their shape from Slack's and Beeper's motion systems; no asset is copied.
///
/// Rules:
/// - Motion in the timeline never changes a row's height. Animate opacity,
///   color, a layer transform, or an overlay only (MATRIX-49 and 50).
/// - Every animation goes through `animation(_:reduceMotion:)`, so Reduce
///   Motion turns it into an instant change. Two exceptions show a change
///   that must still be seen: a count change (MATRIX-193), whose roll
///   becomes a cross-fade through `countTransition(value:reduceMotion:)`,
///   and chrome that comes into place (MATRIX-225), whose settle becomes a
///   short fade through `settleAnimation(reduceMotion:)`.
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

    /// The settle spring (MATRIX-225): chrome that moves into place, with no
    /// visible bounce. Indigo's house spring (41 of its 64 spring sites);
    /// Mosaic also settles at damping 0.85.
    public static let settle: Animation = .spring(response: 0.5, dampingFraction: 0.85)

    /// What Reduce Motion shows in place of the settle (MATRIX-225): a short
    /// fade on the house curve, with no scale and no offset.
    public static let reducedMotionFade: Animation = standard(duration: revealDuration)

    /// The animation of chrome that comes into place or changes in place
    /// (MATRIX-225): the settle spring, or the short fade under Reduce
    /// Motion.
    public static func settleAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedMotionFade : settle
    }

    // MARK: Entrance (MATRIX-225)

    /// The scale transient chrome starts its entrance at, from its anchor.
    public static let entranceScale: CGFloat = 0.96

    /// How far transient chrome starts from its rest place, toward its
    /// anchor, in points.
    public static let entranceDistance: CGFloat = 6

    // MARK: Badge pop (MATRIX-225)

    /// The peak scale of an unread badge's pop when its count goes up.
    public static let badgePopScale: CGFloat = 1.2

    /// The time the pop takes to reach its peak, on an ease curve.
    public static let badgePopRiseDuration: Double = 0.1

    /// The time the pop takes to fall back to rest, on `badgePopSpring`.
    public static let badgePopSettleDuration: Double = 0.35

    /// The spring of the pop's fall: the `pop` spring's values, so the
    /// badge dips a little below rest before it settles.
    public static let badgePopSpring = Spring(response: 0.3, dampingRatio: 0.62)

    /// A count that changes (MATRIX-193): unread badges and reaction tallies.
    /// The house curve at state speed, also under Reduce Motion, where the
    /// content transition is a cross-fade in place of the roll.
    public static let countChange: Animation = standard()

    /// How a count's digits change (MATRIX-193). The digits roll up for a
    /// larger value and down for a smaller one; Reduce Motion cross-fades
    /// them in place.
    ///
    /// - Parameters:
    ///   - value: the number the count shows. Give the capped value for a
    ///     capped badge ("99+"), so a change past the cap does not roll.
    ///   - reduceMotion: the Reduce Motion setting.
    public static func countTransition(value: Double, reduceMotion: Bool) -> ContentTransition {
        reduceMotion ? .opacity : .numericText(value: value)
    }

    /// The animation to use, or nil when Reduce Motion is on.
    public static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

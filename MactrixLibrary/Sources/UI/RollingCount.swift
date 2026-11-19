import SwiftUI
import Tokens

/// The digits of a count that rolls to a new value (MATRIX-193): tabular
/// digits, so a change of one digit never changes the text's width, and the
/// numeric content transition, which rolls up for more and down for fewer.
/// Under Reduce Motion the digits cross-fade.
///
/// The roll needs an animation in the transaction. Put
/// `RollingCountAnimation` on the whole badge, outside its capsule, so the
/// capsule's width also eases when the count gains or loses a digit.
struct RollingCountText: ViewModifier {
    /// The number the count shows, capped as the badge caps it.
    let value: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(MotionToken.countTransition(value: value, reduceMotion: reduceMotion))
    }
}

/// Animates a count change with the house curve (MATRIX-193). It also
/// animates the frame of what it wraps, so a badge capsule eases to its new
/// width. It changes only width: a count is one line of text whatever its
/// value, so no row height changes.
struct RollingCountAnimation: ViewModifier {
    /// The number the count shows, capped as the badge caps it.
    let value: Double

    func body(content: Content) -> some View {
        content.animation(MotionToken.countChange, value: value)
    }
}

extension View {
    /// Tabular digits and the rolling content transition for a count's text.
    func rollingCountText(_ value: Double) -> some View {
        modifier(RollingCountText(value: value))
    }

    /// The house-curve animation for a count change, on the whole badge.
    func rollingCountAnimation(_ value: Double) -> some View {
        modifier(RollingCountAnimation(value: value))
    }
}

/// The display cap of an unread badge (MATRIX-193). Counts above `cap` show
/// as "99+".
enum UnreadCountCap {
    static let cap = 99

    /// The badge text: the count, or "99+" above the cap.
    static func text(_ count: Int) -> String {
        count > cap ? "\(cap)+" : "\(count)"
    }

    /// The value the badge rolls on. Every count above the cap gives the same
    /// value, so a change from 120 to 130 does not roll "99+".
    static func rollValue(_ count: Int) -> Double {
        Double(min(count, cap + 1))
    }
}

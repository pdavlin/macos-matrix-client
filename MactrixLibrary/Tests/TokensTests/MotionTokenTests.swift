import SwiftUI
import Testing
@testable import Tokens

/// Pins the Reduce Motion gate of the motion tokens (MATRIX-135). Every
/// timeline animation goes through `MotionToken.animation(_:reduceMotion:)`,
/// so this gate is what turns motion into an instant change.
@Suite("Motion tokens")
struct MotionTokenTests {
    @Test
    func reduceMotionGivesNoAnimation() {
        #expect(MotionToken.animation(MotionToken.standard(), reduceMotion: true) == nil)
        #expect(MotionToken.animation(MotionToken.pop, reduceMotion: true) == nil)
    }

    @Test
    func withoutReduceMotionTheAnimationPassesThrough() {
        let animation = MotionToken.standard(duration: MotionToken.revealDuration)
        #expect(MotionToken.animation(animation, reduceMotion: false) == animation)
    }

    /// MATRIX-193: a count rolls on its value, so the roll goes up for more
    /// and down for fewer.
    @Test
    func countRollsOnItsValue() {
        #expect(MotionToken.countTransition(value: 10, reduceMotion: false) == .numericText(value: 10))
        #expect(MotionToken.countTransition(value: 10, reduceMotion: false) != .opacity)
    }

    /// MATRIX-193: Reduce Motion cross-fades the digits in place of the roll,
    /// and the change still follows the house curve.
    @Test
    func reduceMotionCrossFadesTheCount() {
        #expect(MotionToken.countTransition(value: 10, reduceMotion: true) == .opacity)
        #expect(MotionToken.countChange == MotionToken.standard())
    }
}

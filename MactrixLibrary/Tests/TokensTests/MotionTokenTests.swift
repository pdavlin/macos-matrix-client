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
}

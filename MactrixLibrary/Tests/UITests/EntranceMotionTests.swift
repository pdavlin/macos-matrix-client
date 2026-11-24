import SwiftUI
import Testing
import Tokens
@testable import UI

/// MATRIX-225: transient chrome settles into place from its anchor, and
/// Reduce Motion makes the entrance a fade only.
@MainActor
struct EntranceMotionTests {
    @Test
    func restIsTheViewAsItIs() {
        #expect(EntranceEffect.rest == EntranceEffect(opacity: 1, scale: 1, offset: .zero))
    }

    /// From the bottom: transparent, a little smaller, a little lower.
    @Test
    func startsBelowFromTheBottom() {
        let start = EntranceEffect.start(from: .bottom, reduceMotion: false)
        #expect(start.opacity == 0)
        #expect(start.scale == MotionToken.entranceScale)
        #expect(start.offset == CGSize(width: 0, height: MotionToken.entranceDistance))
    }

    /// The offset points toward the anchor.
    @Test
    func offsetPointsTowardTheAnchor() {
        let distance = MotionToken.entranceDistance
        #expect(EntranceEffect.start(from: .top, reduceMotion: false).offset == CGSize(width: 0, height: -distance))
        #expect(EntranceEffect.start(from: .leading, reduceMotion: false).offset == CGSize(width: -distance, height: 0))
        #expect(EntranceEffect.start(from: .center, reduceMotion: false).offset == .zero)
    }

    @Test
    func reduceMotionStartsWithNoScaleAndNoOffset() {
        let start = EntranceEffect.start(from: .bottom, reduceMotion: true)
        #expect(start == EntranceEffect(opacity: 0, scale: 1, offset: .zero))
    }

    /// MATRIX-227: the rail name peek grows out of the rail side and
    /// collapses back to it; under Reduce Motion it only fades.
    @Test
    func railPeekGrowsFromTheRailSide() {
        let start = EntranceEffect.start(
            from: .leading,
            scale: MotionToken.railPeekScale,
            distance: MotionToken.railPeekDistance,
            reduceMotion: false
        )
        #expect(start == EntranceEffect(opacity: 0, scale: 0.85, offset: CGSize(width: -8, height: 0)))
        let reduced = EntranceEffect.start(
            from: .leading,
            scale: MotionToken.railPeekScale,
            distance: MotionToken.railPeekDistance,
            reduceMotion: true
        )
        #expect(reduced == EntranceEffect(opacity: 0, scale: 1, offset: .zero))
    }

    /// The settle spring moves it; Reduce Motion fades it.
    @Test
    func animationIsTheSettleOrAShortFade() {
        #expect(MotionToken.settleAnimation(reduceMotion: false) == MotionToken.settle)
        #expect(MotionToken.settleAnimation(reduceMotion: true) == MotionToken.reducedMotionFade)
    }
}

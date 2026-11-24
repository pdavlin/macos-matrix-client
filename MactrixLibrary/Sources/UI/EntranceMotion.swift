import SwiftUI
import Tokens

/// How transient chrome looks before and after its entrance (MATRIX-225).
/// Pure, so the tests can pin it.
///
/// After Mosaic's `PremiumGlassAppearModifier`: the chrome starts
/// transparent, a little smaller from an anchor, and a little toward that
/// anchor, then settles at rest. Under Reduce Motion it starts transparent
/// only: no scale and no offset.
struct EntranceEffect: Equatable {
    var opacity: Double
    var scale: CGFloat
    var offset: CGSize

    /// The look at rest, after the entrance.
    static let rest = EntranceEffect(opacity: 1, scale: 1, offset: .zero)

    /// The look before the entrance.
    ///
    /// - Parameters:
    ///   - anchor: where the chrome grows from. The offset points toward it:
    ///     `.bottom` starts `distance` lower, `.leading` starts `distance`
    ///     to the leading side, `.center` has no offset.
    ///   - scale: the start scale.
    ///   - distance: the start offset, in points.
    ///   - reduceMotion: the Reduce Motion setting.
    static func start(
        from anchor: UnitPoint,
        scale: CGFloat = MotionToken.entranceScale,
        distance: CGFloat = MotionToken.entranceDistance,
        reduceMotion: Bool
    ) -> EntranceEffect {
        guard !reduceMotion else {
            return EntranceEffect(opacity: 0, scale: 1, offset: .zero)
        }
        return EntranceEffect(
            opacity: 0,
            scale: scale,
            offset: CGSize(width: (anchor.x - 0.5) * 2 * distance, height: (anchor.y - 0.5) * 2 * distance)
        )
    }
}

/// Entrance motion for transient chrome (MATRIX-225): the reply and edit
/// bars, the thread reply notice, the Scheduled strip, and the inbox toast.
///
/// When the view appears it settles from `EntranceEffect.start` to rest on
/// `MotionToken.settle`; under Reduce Motion it fades in on
/// `MotionToken.reducedMotionFade`. Opacity, scale, and offset are render
/// effects: the view takes its full size at once, so a measured stack (the
/// composer, MATRIX-198) gets its final height in the same frame. There is
/// no exit motion. Not for timeline rows.
struct EntranceMotion: ViewModifier {
    let anchor: UnitPoint
    let delay: Double

    @State private var hasEntered = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .entranceEffect(hasEntered ? .rest : .start(from: anchor, reduceMotion: reduceMotion), anchor: anchor)
            .onAppear {
                withAnimation(MotionToken.settleAnimation(reduceMotion: reduceMotion).delay(delay)) {
                    hasEntered = true
                }
            }
    }
}

/// The entrance look as a transition, for chrome that also leaves with
/// motion: it goes back the way it came (the rail name peek, MATRIX-227).
/// The animation comes from the transaction.
struct EntranceTransition: Transition {
    let anchor: UnitPoint
    var scale = MotionToken.entranceScale
    var distance = MotionToken.entranceDistance
    let reduceMotion: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        let start = EntranceEffect.start(from: anchor, scale: scale, distance: distance, reduceMotion: reduceMotion)
        content.entranceEffect(phase.isIdentity ? .rest : start, anchor: anchor)
    }
}

private extension View {
    func entranceEffect(_ effect: EntranceEffect, anchor: UnitPoint) -> some View {
        opacity(effect.opacity)
            .scaleEffect(effect.scale, anchor: anchor)
            .offset(effect.offset)
    }
}

public extension View {
    /// Settles the view into place when it appears (MATRIX-225).
    ///
    /// - Parameters:
    ///   - anchor: where the view grows from; `.bottom` for chrome that
    ///     rises out of the composer or the foot of a list.
    ///   - delay: the wait before the entrance starts, in seconds.
    func entranceMotion(from anchor: UnitPoint = .bottom, delay: Double = 0) -> some View {
        modifier(EntranceMotion(anchor: anchor, delay: delay))
    }
}

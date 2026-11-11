import SwiftUI
import Tokens

/// Fades and slides a hover overlay into place (MATRIX-135). The hover
/// action bar uses it (`HoverActionBar`).
///
/// On reveal the content fades in and slides `MotionToken.revealOffset` up
/// into its resting place over `MotionToken.revealDuration`. On hide it fades
/// out where it is; its offset resets for the next reveal only after the fade
/// ends, so it does not drift down as it goes. With Reduce Motion on, the
/// content shows and hides at once and does not slide.
///
/// Content that appears already revealed also fades and slides in. The
/// timeline's floating bar gives each row's bar its own identity, so the
/// bar reveals again when the pointer moves to another row (MATRIX-145), as
/// it did when each row drew its own bar.
///
/// Opacity and offset are render effects: the modifier never changes the
/// layout of the view it wraps. Hidden content takes no clicks.
struct HoverRevealModifier: ViewModifier {
    /// Whether the content shows.
    let isRevealed: Bool

    @State private var isShown = false
    /// The latest `isRevealed`, kept in state so the fade-out's completion
    /// reads the current value, not the one captured when the fade started.
    @State private var wantsReveal = false
    @State private var offset: CGFloat = MotionToken.revealOffset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .onAppear {
                if isRevealed {
                    update(revealed: true)
                }
            }
            .onChange(of: isRevealed) { _, revealed in
                update(revealed: revealed)
            }
    }

    private func update(revealed: Bool) {
        wantsReveal = revealed
        guard let animation = MotionToken.animation(
            MotionToken.standard(duration: MotionToken.revealDuration),
            reduceMotion: reduceMotion
        ) else {
            isShown = revealed
            offset = 0
            return
        }

        if revealed {
            withAnimation(animation) {
                isShown = true
                offset = 0
            }
        } else {
            withAnimation(animation, completionCriteria: .logicallyComplete) {
                isShown = false
            } completion: {
                // Content that was revealed again during the fade stays put.
                if !wantsReveal {
                    offset = MotionToken.revealOffset
                }
            }
        }
    }
}

extension View {
    /// Fades and slides this view into place while `isRevealed` is true. See
    /// `HoverRevealModifier`.
    func hoverReveal(_ isRevealed: Bool) -> some View {
        modifier(HoverRevealModifier(isRevealed: isRevealed))
    }
}

import Models
import SwiftUI
import Tokens

/// When an unread badge pops (MATRIX-225). Pure, so the tests can pin it.
///
/// A badge pops when the count it pops on goes up. It does not pop when the
/// count goes down or stays, on its first appearance (no change has
/// happened yet), or under Reduce Motion.
enum BadgePopRule {
    /// Whether a change of the count from `old` to `new` pops the badge.
    static func shouldPop(from old: Int, to new: Int, reduceMotion: Bool) -> Bool {
        !reduceMotion && new > old
    }

    /// The count a chat-list unread indicator pops on: the unread count, or
    /// 0 for a muted chat. A muted chat never pops, because mute asks for
    /// quiet.
    static func count(of unread: ChatListUnread) -> Int {
        unread.isMuted ? 0 : Int(clamping: unread.count)
    }

    /// The count a rail badge pops on: its count, or 0 for a dot or no mark.
    /// A dot is activity that does not count (muted chats), so it does not
    /// pop; a dot that becomes a count does.
    static func count(of badge: ChatLabelBadge) -> Int {
        if case let .count(count) = badge {
            return count
        }
        return 0
    }
}

/// A short scale pulse on a badge when its count goes up (MATRIX-225),
/// after Mosaic's `ScoreChangePulseModifier`: a keyframe animation on an
/// integer trigger that moves only on an increase.
///
/// The badge scales to `MotionToken.badgePopScale` over
/// `MotionToken.badgePopRiseDuration`, then falls back to rest on
/// `MotionToken.badgePopSpring` over `MotionToken.badgePopSettleDuration`.
/// It is a scale effect only, so no layout and no row height changes. The
/// MATRIX-193 digit roll runs at the same time. No pulse under Reduce
/// Motion.
struct BadgePop: ViewModifier {
    /// The count the pulse watches (`BadgePopRule.count(of:)`).
    let count: Int

    /// Moves once for each pop. The keyframes run each time it changes.
    @State private var pops = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: CGFloat(1), trigger: pops) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(MotionToken.badgePopScale, duration: MotionToken.badgePopRiseDuration)
                    SpringKeyframe(1, duration: MotionToken.badgePopSettleDuration, spring: MotionToken.badgePopSpring)
                }
            }
            // Without `initial`, so the first appearance does not pop.
            .onChange(of: count) { old, new in
                if BadgePopRule.shouldPop(from: old, to: new, reduceMotion: reduceMotion) {
                    pops &+= 1
                }
            }
    }
}

public extension View {
    /// Pops the view once each time `count` goes up (MATRIX-225).
    func badgePop(count: Int) -> some View {
        modifier(BadgePop(count: count))
    }
}

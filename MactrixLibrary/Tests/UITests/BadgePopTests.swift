import Models
import SwiftUI
import Testing
@testable import UI

/// MATRIX-225: an unread badge pops when its count goes up, and only then.
///
/// The rule tests pin the trigger: up pops; down, the same count, and
/// Reduce Motion do not. The first appearance cannot pop, because the
/// modifier watches changes without `initial`. The structure tests read
/// each badge's `Body` type, which names the modifiers it applies.
@MainActor
struct BadgePopTests {
    // MARK: Rule

    @Test
    func anIncreasePops() {
        #expect(BadgePopRule.shouldPop(from: 0, to: 1, reduceMotion: false))
        #expect(BadgePopRule.shouldPop(from: 3, to: 4, reduceMotion: false))
        #expect(BadgePopRule.shouldPop(from: 99, to: 120, reduceMotion: false))
    }

    @Test
    func aDecreaseOrTheSameCountDoesNotPop() {
        #expect(!BadgePopRule.shouldPop(from: 4, to: 3, reduceMotion: false))
        #expect(!BadgePopRule.shouldPop(from: 1, to: 0, reduceMotion: false))
        #expect(!BadgePopRule.shouldPop(from: 5, to: 5, reduceMotion: false))
    }

    @Test
    func reduceMotionNeverPops() {
        #expect(!BadgePopRule.shouldPop(from: 0, to: 1, reduceMotion: true))
        #expect(!BadgePopRule.shouldPop(from: 3, to: 40, reduceMotion: true))
    }

    // MARK: What each badge pops on

    @Test
    func chatListCountPopsOnItsCount() {
        #expect(BadgePopRule.count(of: ChatListUnread(count: 7, isUnread: true)) == 7)
        #expect(BadgePopRule.count(of: ChatListUnread()) == 0)
    }

    /// A muted chat keeps its gray capsule but never pops.
    @Test
    func mutedChatDoesNotPop() {
        let before = BadgePopRule.count(of: ChatListUnread(count: 2, isUnread: true, isMuted: true))
        let after = BadgePopRule.count(of: ChatListUnread(count: 3, isUnread: true, isMuted: true))
        #expect(!BadgePopRule.shouldPop(from: before, to: after, reduceMotion: false))
    }

    /// A dot is uncounted activity: no mark to a dot does not pop, a dot to
    /// a count does, and a count to a dot does not.
    @Test
    func railBadgePopsOnlyOnACount() {
        let none = BadgePopRule.count(of: ChatLabelBadge.none)
        let dot = BadgePopRule.count(of: .dot)
        let one = BadgePopRule.count(of: .count(1))
        let two = BadgePopRule.count(of: .count(2))
        #expect(!BadgePopRule.shouldPop(from: none, to: dot, reduceMotion: false))
        #expect(BadgePopRule.shouldPop(from: dot, to: one, reduceMotion: false))
        #expect(BadgePopRule.shouldPop(from: none, to: one, reduceMotion: false))
        #expect(BadgePopRule.shouldPop(from: one, to: two, reduceMotion: false))
        #expect(!BadgePopRule.shouldPop(from: two, to: dot, reduceMotion: false))
    }

    // MARK: Structure

    private func bodyTypeName<V: View>(of _: V.Type) -> String {
        String(reflecting: V.Body.self)
    }

    @Test
    func chatListBadgePops() {
        #expect(bodyTypeName(of: ChatListUnreadIndicator.self).contains("BadgePop"))
    }

    @Test
    func railBadgePops() {
        #expect(bodyTypeName(of: LabelBadgeView.self).contains("BadgePop"))
    }
}

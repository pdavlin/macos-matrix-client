import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-193: unread badges and reaction tallies roll to a new value.
///
/// The structural tests read each count view's `Body` type, which names the
/// modifiers the view applies, so they show that the count uses the rolling
/// transition and its animation. The size tests show tabular digits: a count
/// of 1 and a count of 8 have the same width. The snapshots show the end
/// state of counts 1, 9, 10, and 99+ (the badge cap) in light and dark;
/// animations are not captured.
@MainActor
struct RollingCountTests {
    private nonisolated static let ownUserId = "@me:example.org"

    private struct Sender: ReactionSenderData {
        let senderId: String
        let date = Date(timeIntervalSince1970: 0)
    }

    private struct CountReaction: Reaction {
        let key: String
        let senders: [Sender]

        var id: String {
            "\(key)-\(senders.count)"
        }

        init(count: Int, includesOwn: Bool = false) {
            key = "👍"
            senders = (0 ..< count).map { index in
                Sender(senderId: includesOwn && index == 0 ? RollingCountTests.ownUserId : "@user\(index):example.org")
            }
        }
    }

    /// The counts the snapshots show. 120 draws as "99+".
    private static let counts = [1, 9, 10, 120]

    // MARK: Structure

    private func bodyTypeName<V: View>(of _: V.Type) -> String {
        String(reflecting: V.Body.self)
    }

    @Test
    func chatListBadgeRollsItsCount() {
        let name = bodyTypeName(of: ChatListUnreadIndicator.self)
        #expect(name.contains("RollingCountText"))
        #expect(name.contains("RollingCountAnimation"))
    }

    @Test
    func railBadgeRollsItsCount() {
        let name = bodyTypeName(of: LabelBadgeView.self)
        #expect(name.contains("RollingCountText"))
        #expect(name.contains("RollingCountAnimation"))
    }

    @Test
    func reactionChipRollsItsCount() {
        let name = bodyTypeName(of: MessageReactionView<CountReaction>.self)
        #expect(name.contains("RollingCountText"))
        #expect(name.contains("RollingCountAnimation"))
    }

    // MARK: Tabular digits

    private func fittingSize(_ view: some View) -> CGSize {
        NSHostingController(rootView: view).view.fittingSize
    }

    /// The test font draws "1" narrower than "8" when its digits are
    /// proportional, so the size tests below show the tabular digits.
    @Test
    func proportionalDigitsDifferInWidth() {
        let font = Font.system(size: 10, weight: .bold)
        #expect(fittingSize(Text("1").font(font)).width < fittingSize(Text("8").font(font)).width)
    }

    @Test
    func chatListBadgeUsesTabularDigits() {
        let one = fittingSize(ChatListUnreadIndicator(unread: ChatListUnread(count: 11, isUnread: true)))
        let eight = fittingSize(ChatListUnreadIndicator(unread: ChatListUnread(count: 88, isUnread: true)))
        #expect(one == eight)
    }

    @Test
    func railBadgeUsesTabularDigits() {
        #expect(fittingSize(LabelBadgeView(badge: .count(11))) == fittingSize(LabelBadgeView(badge: .count(88))))
    }

    @Test
    func reactionChipUsesTabularDigits() {
        let one = fittingSize(MessageReactionView(reaction: CountReaction(count: 1), active: .constant(false)))
        let eight = fittingSize(MessageReactionView(reaction: CountReaction(count: 8), active: .constant(false)))
        #expect(one == eight)
    }

    @Test
    func badgeCapsAtNinetyNine() {
        #expect(UnreadCountCap.text(99) == "99")
        #expect(UnreadCountCap.text(100) == "99+")
        #expect(UnreadCountCap.rollValue(120) == UnreadCountCap.rollValue(100))
        #expect(UnreadCountCap.rollValue(99) < UnreadCountCap.rollValue(100))
    }

    // MARK: Snapshots

    private func host(_ view: some View, appearance: NSAppearance.Name) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance, so the snapshot does not follow the system's.
        controller.view.appearance = NSAppearance(named: appearance)
        return controller
    }

    private var chatListBadges: some View {
        HStack(spacing: 8) {
            ForEach(Self.counts, id: \.self) { count in
                ChatListUnreadIndicator(unread: ChatListUnread(count: UInt64(count), isUnread: true))
            }
        }
    }

    private var railBadges: some View {
        HStack(spacing: 8) {
            ForEach(Self.counts, id: \.self) { count in
                LabelBadgeView(badge: .count(count))
            }
        }
    }

    private var reactionChips: some View {
        HStack(spacing: 8) {
            ForEach(Self.counts, id: \.self) { count in
                MessageReactionView(reaction: CountReaction(count: count, includesOwn: count == 10), active: .constant(count == 10))
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func chatListBadgesLight() {
        assertSnapshot(of: host(chatListBadges, appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func chatListBadgesDark() {
        assertSnapshot(of: host(chatListBadges, appearance: .darkAqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func railBadgesLight() {
        assertSnapshot(of: host(railBadges, appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func railBadgesDark() {
        assertSnapshot(of: host(railBadges, appearance: .darkAqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func reactionChipsLight() {
        assertSnapshot(of: host(reactionChips, appearance: .aqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func reactionChipsDark() {
        assertSnapshot(of: host(reactionChips, appearance: .darkAqua), as: .scaledImage)
    }
}

import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshots of the reaction chips (MATRIX-135): the account's own reaction,
/// another user's reaction, a strip of several, and large tallies.
///
/// Animations are not captured; each image is the end state. The hover ring
/// of another user's reaction needs a pointer and is not shown.
@MainActor
struct ReactionChipSnapshotTests {
    private nonisolated static let ownUserId = "@me:example.org"

    private struct Sender: ReactionSenderData {
        let senderId: String
        let date = Date(timeIntervalSince1970: 0)
    }

    private struct ChipReaction: Reaction {
        let key: String
        let senders: [Sender]

        var id: String {
            key
        }

        /// A reaction with `count` senders. The first sender is the account's
        /// own user when `includesOwn` is true.
        init(key: String, count: Int, includesOwn: Bool) {
            self.key = key
            senders = (0 ..< count).map { index in
                Sender(senderId: includesOwn && index == 0 ? ReactionChipSnapshotTests.ownUserId : "@user\(index):example.org")
            }
        }

        var isOwn: Bool {
            senders.contains { $0.senderId == ReactionChipSnapshotTests.ownUserId }
        }
    }

    private func strip(_ reactions: [ChipReaction]) -> some View {
        HStack {
            ForEach(reactions) { reaction in
                MessageReactionView(reaction: reaction, active: .constant(reaction.isOwn))
            }
        }
    }

    private func snapshot(of view: some View) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance: an unpinned snapshot flips with light/dark mode.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    /// Accent tint, inset accent ring, semibold tally.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func ownReaction() {
        assertSnapshot(
            of: snapshot(of: strip([ChipReaction(key: "👍", count: 2, includesOwn: true)])),
            as: .scaledImage
        )
    }

    /// Quiet fill, no ring at rest, regular tally.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func otherReaction() {
        assertSnapshot(
            of: snapshot(of: strip([ChipReaction(key: "👍", count: 2, includesOwn: false)])),
            as: .scaledImage
        )
    }

    /// Own and other chips side by side, with a text key among the emoji.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func multipleReactions() {
        assertSnapshot(
            of: snapshot(of: strip([
                ChipReaction(key: "😄", count: 1, includesOwn: true),
                ChipReaction(key: "🎉", count: 3, includesOwn: false),
                ChipReaction(key: "lgtm", count: 1, includesOwn: false),
            ])),
            as: .scaledImage
        )
    }

    /// Three-digit tallies keep the capsule's height.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func largeCount() {
        assertSnapshot(
            of: snapshot(of: strip([
                ChipReaction(key: "🔥", count: 128, includesOwn: true),
                ChipReaction(key: "👀", count: 999, includesOwn: false),
            ])),
            as: .scaledImage
        )
    }

    /// The chip's size does not depend on whether the reaction is the
    /// account's own: the ring is an inset stroke and the tally reserves its
    /// semibold width. The row measurement and `ReactionPillGeometry` rely on
    /// this, because the own-reaction flag is not a height input.
    @Test
    func ownAndOtherChipsHaveTheSameSize() {
        let own = NSHostingController(rootView: strip([ChipReaction(key: "👍", count: 12, includesOwn: true)]))
        let other = NSHostingController(rootView: strip([ChipReaction(key: "👍", count: 12, includesOwn: false)]))
        #expect(own.view.fittingSize == other.view.fittingSize)
    }
}

import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// A message with the fields a run reads: who, when, and whether it is ours.
private struct RhythmEvent: Models.EventTimelineItem {
    let sender: String
    let name: String
    let date: Date
    var isOwn = false

    var isRemote: Bool { true }
    var senderProfileDetails: ProfileDetails { .ready(displayName: name, displayNameAmbiguous: false, avatarUrl: nil) }
    var isEditable: Bool { false }
    var sendState: LocalSendState? { nil }
    var localCreatedAt: UInt64? { nil }
    var userReadReceipts: [String: Receipt] { [:] }
    var canBeRepliedTo: Bool { true }
    var userId: String { sender }
    var displayName: String? { name }
    var avatarUrl: String? { nil }
}

/// MATRIX-68: sender grouping, the gap rhythm, and sender colors, rendered
/// through the same `MessageRunRow` composition the app's `ChatMessageView`
/// uses.
///
/// Groupings are derived by `TimelineRowGrouping.derive`, not written by hand,
/// so these images show what the rule produces. Dates are built in the
/// machine's own calendar, so the timestamp column reads the same wall-clock
/// time whatever zone the test runs in.
///
/// Snapshot references render at a fixed 2x through `.scaledImage` (S-26).
@MainActor
struct MessageRhythmSnapshotTests {
    private static let ada = (id: "@ada:example.org", name: "Ada Lovelace")
    private static let bob = (id: "@bob:example.org", name: "Bob Kahn")
    private static let alice = (id: "@alice:example.org", name: "Alice Liddell")
    private static let own = (id: "@patrick:example.org", name: "Patrick")

    /// 09:00 local on a fixed day, plus `seconds`.
    private static func at(_ seconds: TimeInterval) -> Date {
        let components = DateComponents(year: 2026, month: 10, day: 23, hour: 9, minute: 0)
        let base = Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
        return base.addingTimeInterval(seconds)
    }

    private static func event(
        _ sender: (id: String, name: String),
        at seconds: TimeInterval,
        isOwn: Bool = false
    ) -> RhythmEvent {
        RhythmEvent(sender: sender.id, name: sender.name, date: at(seconds), isOwn: isOwn)
    }

    private struct GroupedRow {
        let id: Int
        let event: RhythmEvent
        let text: String
        let grouping: TimelineRowGrouping
    }

    /// Lays out `messages` oldest first, each grouped against the one before.
    private func run(_ messages: [(event: RhythmEvent, text: String)]) -> some View {
        var previous: TimelineGroupingAnchor?
        var rows: [GroupedRow] = []
        for (index, message) in messages.enumerated() {
            let anchor = TimelineGroupingAnchor(senderId: message.event.sender, date: message.event.date)
            let grouping = TimelineRowGrouping.derive(anchor, after: previous, calendar: .current)
            rows.append(GroupedRow(id: index, event: message.event, text: message.text, grouping: grouping))
            previous = anchor
        }

        return VStack(spacing: 0) {
            ForEach(rows, id: \.id) { row in
                MessageRunRow(grouping: row.grouping) {
                    MessageEventProfileView(event: row.event, actions: MockMessageEventActions(), imageLoader: nil)
                } message: {
                    MessageEventBodyView(
                        event: row.event,
                        focused: false,
                        reactions: [MockReaction](),
                        actions: MockMessageEventActions(),
                        ownUserID: Self.own.id,
                        imageLoader: nil,
                        roomMembers: [MockRoomMember]()
                    ) {
                        Text(row.text)
                    }
                }
            }
        }
    }

    private func snapshot(
        of view: some View,
        appearance: NSAppearance.Name = .aqua,
        width: CGFloat = 420
    ) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: width)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance: an unpinned snapshot flips with light/dark mode
        // and fails by time of day.
        controller.view.appearance = NSAppearance(named: appearance)
        return controller
    }

    /// Three messages inside a minute: one header, two continuations at the
    /// tightest gap, and the body text of all three on one column.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func runOfThreeFromOneSender() {
        let view = run([
            (Self.event(Self.ada, at: 0), "Has anyone seen the engine notes?"),
            (Self.event(Self.ada, at: 20), "The ones from Tuesday."),
            (Self.event(Self.ada, at: 40), "Never mind, found them."),
        ])
        assertSnapshot(of: snapshot(of: view), as: .scaledImage)
    }

    /// A sender change inside a minute starts a new run with a header and
    /// the turn gap, in both directions.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func senderChange() {
        let view = run([
            (Self.event(Self.ada, at: 0), "Ready for review?"),
            (Self.event(Self.bob, at: 30), "Give me five minutes."),
            (Self.event(Self.ada, at: 50), "Sure."),
        ])
        assertSnapshot(of: snapshot(of: view), as: .scaledImage)
    }

    /// Every band in one strip, top to bottom: none (first row), same-sender
    /// burst, sender turn, short pause, pause, long pause.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func everyGapBand() {
        let view = run([
            (Self.event(Self.ada, at: 0), "First message: no gap."),
            (Self.event(Self.ada, at: 30), "Same sender, 30s later: 2pt."),
            (Self.event(Self.bob, at: 45), "Other sender, 15s later: 4pt."),
            (Self.event(Self.bob, at: 225), "Three minutes later: 4pt."),
            (Self.event(Self.bob, at: 825), "Ten minutes later: 13pt."),
            (Self.event(Self.bob, at: 18825), "Five hours later: 26pt."),
        ])
        assertSnapshot(of: snapshot(of: view), as: .scaledImage)
    }

    /// Two other senders in their palette slots (Alice slot 6 indigo, Bob
    /// slot 3 purple) and an own message in the default text color.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func coloredSenderNames() {
        let view = run([
            (Self.event(Self.alice, at: 0), "Indigo."),
            (Self.event(Self.bob, at: 10), "Purple."),
            (Self.event(Self.own, at: 20, isOwn: true), "Default text color."),
        ])
        assertSnapshot(of: snapshot(of: view), as: .scaledImage)
    }

    /// The same names in the dark palette.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func coloredSenderNamesDark() {
        let view = run([
            (Self.event(Self.alice, at: 0), "Indigo."),
            (Self.event(Self.bob, at: 10), "Purple."),
            (Self.event(Self.own, at: 20, isOwn: true), "Default text color."),
        ])
        assertSnapshot(of: snapshot(of: view, appearance: .darkAqua), as: .scaledImage)
    }
}

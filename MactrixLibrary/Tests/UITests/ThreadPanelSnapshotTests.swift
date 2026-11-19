import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// A thread summary with a set reply count and latest reply.
private struct StubThreadSummary: ThreadSummary {
    let replies: UInt64
    var latest: String? = "fixed, rerun now"

    func numReplies() -> UInt64 {
        replies
    }

    var description: String? {
        latest
    }
}

/// A message with a fixed sender and time.
private struct ThreadEvent: Models.EventTimelineItem {
    var sender = "@ben:example.org"
    var name = "Ben"

    var isRemote: Bool { true }
    var senderProfileDetails: ProfileDetails { .ready(displayName: name, displayNameAmbiguous: false, avatarUrl: nil) }
    var isOwn: Bool { false }
    var isEditable: Bool { false }
    var date: Date {
        let components = DateComponents(year: 2026, month: 11, day: 19, hour: 10, minute: 42)
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    var sendState: LocalSendState? { nil }
    var localCreatedAt: UInt64? { nil }
    var userReadReceipts: [String: Receipt] { [:] }
    var canBeRepliedTo: Bool { true }
    var userId: String { sender }
    var displayName: String? { name }
    var avatarUrl: String? { nil }
}

/// MATRIX-183: the thread panel header, the main-column thread chip, the
/// panel root with its band, and the main-column root with the open-thread
/// mark, in light and dark.
///
/// Same capture as the other row snapshots: a fixed 2x scale and a pinned
/// appearance. The height checks also run on CI, because they do not depend
/// on font rasterization.
@MainActor
struct ThreadPanelSnapshotTests {
    private func host(
        _ view: some View,
        width: CGFloat = 420,
        appearance: NSAppearance.Name = .aqua
    ) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: width)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance, so the snapshot does not follow the system's.
        controller.view.appearance = NSAppearance(named: appearance)
        return controller
    }

    private nonisolated static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    private func name(_ appearance: NSAppearance.Name) -> String {
        appearance == .darkAqua ? "dark" : "light"
    }

    // MARK: Header

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func header(appearance: NSAppearance.Name) {
        assertSnapshot(
            of: host(ThreadTimelineHeader(roomName: "#general", replyCount: 4) {}, width: 400, appearance: appearance),
            as: .scaledImage,
            named: name(appearance)
        )
    }

    /// One reply: singular noun.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func headerOneReply() {
        assertSnapshot(of: host(ThreadTimelineHeader(roomName: "#general", replyCount: 1) {}, width: 400), as: .scaledImage)
    }

    /// The count is not known yet: the room only.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func headerLoading() {
        assertSnapshot(of: host(ThreadTimelineHeader(roomName: "#general", replyCount: nil) {}, width: 400), as: .scaledImage)
    }

    // MARK: Chip

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func chipOneReply(appearance: NSAppearance.Name) {
        let chip = MessageThreadSummary(summary: StubThreadSummary(replies: 1)) {}
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        assertSnapshot(of: host(chip, appearance: appearance), as: .scaledImage, named: name(appearance))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func chipManyReplies(appearance: NSAppearance.Name) {
        let chip = MessageThreadSummary(summary: StubThreadSummary(replies: 12)) {}
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        assertSnapshot(of: host(chip, appearance: appearance), as: .scaledImage, named: name(appearance))
    }

    // MARK: Rows

    /// A message row as `ChatMessageView` draws it, with an optional chip.
    private func row(text: String, focused: Bool = false, chip: ThreadSummary? = nil) -> some View {
        MessageRunRow(grouping: TimelineRowGrouping(isContinuation: false, gap: .none)) {
            MessageEventProfileView(event: ThreadEvent(), actions: MockMessageEventActions(), imageLoader: nil)
        } message: {
            MessageEventBodyView(
                event: ThreadEvent(),
                focused: focused,
                reactions: [MockReaction](),
                actions: MockMessageEventActions(),
                ownUserID: "@me:example.org",
                imageLoader: nil,
                roomMembers: [MockRoomMember]()
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text)
                    if let chip {
                        MessageThreadSummary(summary: chip) {}
                    }
                }
            }
        }
    }

    /// The panel root: the band and the accent bar, no chip.
    private func panelRoot(isRoot: Bool = true) -> some View {
        row(text: "It failed on step 3.")
            .environment(\.timelineRowIsThreadRoot, isRoot)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func panelRootBand(appearance: NSAppearance.Name) {
        assertSnapshot(of: host(panelRoot(), width: 400, appearance: appearance), as: .scaledImage, named: name(appearance))
    }

    /// The band and the bar are a background and an overlay: the root row
    /// has the height of the same row without them.
    @Test(arguments: [200, 400] as [CGFloat])
    func panelRootBandKeepsTheRowHeight(width: CGFloat) {
        let banded = host(panelRoot(isRoot: true), width: width).view.fittingSize.height
        let plain = host(panelRoot(isRoot: false), width: width).view.fittingSize.height
        #expect(banded == plain)
    }

    /// The main-column root of the open thread: the focus background around
    /// the body and the chip.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func mainColumnOpenRootMark(appearance: NSAppearance.Name) {
        let view = row(text: "It failed on step 3.", focused: true, chip: StubThreadSummary(replies: 4))
        assertSnapshot(of: host(view, appearance: appearance), as: .scaledImage, named: name(appearance))
    }

    /// The mark is the focus background: on or off, the row keeps its height.
    @Test(arguments: [240, 420] as [CGFloat])
    func openRootMarkKeepsTheRowHeight(width: CGFloat) {
        let summary = StubThreadSummary(replies: 4)
        let marked = host(row(text: "It failed on step 3.", focused: true, chip: summary), width: width).view.fittingSize.height
        let plain = host(row(text: "It failed on step 3.", focused: false, chip: summary), width: width).view.fittingSize.height
        #expect(marked == plain)
    }
}

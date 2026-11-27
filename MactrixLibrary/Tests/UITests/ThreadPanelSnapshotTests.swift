import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
import Tokens
@testable import UI

/// A thread summary with a set reply count, latest reply, and repliers.
private struct StubThreadSummary: ThreadSummary {
    let replies: UInt64
    var latest: String? = "fixed, rerun now"
    var repliers: [ThreadReplier] = [StubThreadSummary.cy]

    static let cy = ThreadReplier(userId: "@cy:example.org", displayName: "Cy", avatarUrl: nil)
    static let ana = ThreadReplier(userId: "@ana:example.org", displayName: "Ana", avatarUrl: nil)
    static let dee = ThreadReplier(userId: "@dee:example.org", displayName: "Dee", avatarUrl: nil)
    static let ed = ThreadReplier(userId: "@ed:example.org", displayName: "Ed", avatarUrl: nil)

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

    /// MATRIX-261: the header with the Follow control, before the close
    /// button: an outline bell when not followed, a filled tinted bell when
    /// followed.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances, [false, true])
    func headerWithFollowControl(appearance: NSAppearance.Name, followed: Bool) {
        let follow = ThreadFollowControl(state: followed ? .followed : .notFollowed)
        assertSnapshot(
            of: host(ThreadTimelineHeader(roomName: "#general", replyCount: 4, follow: follow) {}, width: 400, appearance: appearance),
            as: .scaledImage,
            named: "\(followed ? "followed" : "notFollowed")-\(name(appearance))"
        )
    }

    /// The control does not change the header's height, in any state.
    @Test func followControlKeepsTheHeaderHeight() {
        let plain = host(ThreadTimelineHeader(roomName: "#general", replyCount: 4) {}, width: 400).view.fittingSize.height
        let states: [ThreadFollowState] = [.reading, .notFollowed, .followed, .changing(toFollowed: true)]
        for state in states {
            let header = ThreadTimelineHeader(roomName: "#general", replyCount: 4, follow: ThreadFollowControl(state: state)) {}
            #expect(host(header, width: 400).view.fittingSize.height == plain)
        }
    }

    // MARK: Chip

    private func chip(_ summary: StubThreadSummary) -> some View {
        MessageThreadSummary(summary: summary) {}
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
    }

    /// One reply: singular noun, the latest sender's avatar.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func chipOneReply(appearance: NSAppearance.Name) {
        assertSnapshot(of: host(chip(StubThreadSummary(replies: 1)), appearance: appearance), as: .scaledImage, named: name(appearance))
    }

    /// Many replies with one avatar: what the SDK summary gives (the latest
    /// reply's sender only).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func chipManyRepliesOneAvatar(appearance: NSAppearance.Name) {
        assertSnapshot(of: host(chip(StubThreadSummary(replies: 12)), appearance: appearance), as: .scaledImage, named: name(appearance))
    }

    /// Four repliers given: the chip shows the first three.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func chipThreeAvatars(appearance: NSAppearance.Name) {
        let summary = StubThreadSummary(
            replies: 4,
            repliers: [StubThreadSummary.cy, StubThreadSummary.ana, StubThreadSummary.dee, StubThreadSummary.ed]
        )
        assertSnapshot(of: host(chip(summary), appearance: appearance), as: .scaledImage, named: name(appearance))
    }

    /// The latest reply is not loaded: no avatar and no latest-reply text.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func chipLatestReplyNotLoaded() {
        assertSnapshot(of: host(chip(StubThreadSummary(replies: 2, latest: nil, repliers: []))), as: .scaledImage)
    }

    /// The chip's height does not depend on the avatars or the latest reply,
    /// which the row height fingerprint does not hold.
    @Test(arguments: [240, 420] as [CGFloat])
    func chipHeightIsTheSameForEveryForm(width: CGFloat) {
        let forms = [
            StubThreadSummary(replies: 2, latest: nil, repliers: []),
            StubThreadSummary(replies: 1),
            StubThreadSummary(replies: 4, repliers: [StubThreadSummary.cy, StubThreadSummary.ana, StubThreadSummary.dee]),
            StubThreadSummary(replies: 120, latest: String(repeating: "a long latest reply ", count: 20)),
        ]
        let heights = Set(forms.map { host(chip($0), width: width).view.fittingSize.height })
        #expect(heights.count == 1)
    }

    // MARK: Divider

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func repliesDivider(appearance: NSAppearance.Name) {
        assertSnapshot(
            of: host(VirtualItemView(item: .threadReplies(count: 4)), width: 400, appearance: appearance),
            as: .scaledImage,
            named: name(appearance)
        )
    }

    /// The row measurement skips the divider at `ThreadRepliesDivider.rowHeight`
    /// (Models). The constant, the token, and the drawn row must agree at
    /// every width.
    @Test(arguments: [80, 200, 400, 900] as [CGFloat])
    func repliesDividerHasTheFixedRowHeight(width: CGFloat) {
        let row = ThreadRepliesDivider.row(count: 4)
        #expect(ThreadRepliesDivider.rowHeight == ThreadToken.repliesDividerHeight)
        #expect(row.fixedHeight == ThreadToken.repliesDividerHeight)
        for count in [1, 4, 1200] {
            let height = host(VirtualItemView(item: .threadReplies(count: count)), width: width).view.fittingSize.height
            #expect(height == ThreadToken.repliesDividerHeight)
        }
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

    /// The top of the panel: the root with its band, the divider, and a
    /// reply.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func panelRootDividerAndReply(appearance: NSAppearance.Name) {
        let panel = VStack(spacing: 0) {
            panelRoot()
            VirtualItemView(item: .threadReplies(count: 3))
            row(text: "Looking")
        }
        assertSnapshot(of: host(panel, width: 400, appearance: appearance), as: .scaledImage, named: name(appearance))
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

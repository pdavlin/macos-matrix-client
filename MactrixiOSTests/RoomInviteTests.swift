@testable import MactrixiOS
import Models
import SwiftUI
import UIKit
import XCTest

/// A membership a test can change while the switch is on screen. At file
/// scope because the `@Observable` expansion cannot reach a private nested
/// class.
@Observable
private final class MembershipFixture {
    var membership: Models.Membership

    init(_ membership: Models.Membership) {
        self.membership = membership
    }
}

/// MATRIX-104: an invited room shows Accept and Reject, an accepted invite
/// opens the timeline, and a rejected invite closes the room.
///
/// The membership switch and the shell are hosted in a window with fixture
/// screens, as `RoomNavigationTests` does, so no account or SDK room is
/// needed. The invite model runs on stub calls.
@MainActor
final class RoomInviteTests: XCTestCase {
    private struct Refused: Error {}

    /// The screens that appeared and disappeared, in order.
    private final class ScreenLog {
        var events: [String] = []
    }

    /// Counts the stub calls.
    private final class CallCounter {
        var accepts = 0
        var rejects = 0
    }

    /// The hosting window, hidden by a teardown block.
    private var window: UIWindow?

    // MARK: - Membership switch

    func testInvitedRoomShowsTheInviteScreen() {
        let log = hostSwitch(MembershipFixture(.invited))

        XCTAssertTrue(waitUntil { log.events.contains("invite") }, "the invited room did not show the invite screen")
        XCTAssertFalse(waitForTimeline(timeout: 0.5))
    }

    func testJoinedRoomShowsTheTimeline() {
        let log = hostSwitch(MembershipFixture(.joined))

        XCTAssertTrue(waitForTimeline(), "the joined room did not show the timeline container")
        XCTAssertFalse(log.events.contains("invite"))
    }

    func testLeftRoomShowsNeitherScreen() {
        let log = hostSwitch(MembershipFixture(.left))

        XCTAssertFalse(waitForTimeline(timeout: 0.5))
        XCTAssertFalse(log.events.contains("invite"))
    }

    func testAcceptedInviteOpensTheTimelineInPlace() {
        let fixture = MembershipFixture(.invited)
        let log = hostSwitch(fixture)
        XCTAssertTrue(waitUntil { log.events.contains("invite") })

        fixture.membership = .joined

        XCTAssertTrue(waitForTimeline(), "the joined membership did not open the timeline")
    }

    // MARK: - Close action

    func testClosingTheRoomPopsItOnIPhone() {
        let log = hostShell(usesStack: true, openedRoomID: "!dm1")

        XCTAssertTrue(waitUntil { log.events.contains("disappear !dm1") }, "events: \(log.events)")
    }

    func testClosingTheRoomClearsTheSelectionOnIPad() {
        let log = hostShell(usesStack: false, openedRoomID: "!room1")

        XCTAssertTrue(waitUntil { log.events.contains("disappear !room1") }, "events: \(log.events)")
    }

    func testClosingPopsTheRoomAndWhatIsAboveIt() {
        XCTAssertEqual(RoomClosing.path(["!a", "!b"], closing: "!a"), [])
        XCTAssertEqual(RoomClosing.path(["!a", "!b"], closing: "!b"), ["!a"])
    }

    func testClosingARoomThatIsNotOpenChangesNothing() {
        XCTAssertEqual(RoomClosing.path(["!a"], closing: "!gone"), ["!a"])
        XCTAssertEqual(RoomClosing.selection("!a", closing: "!gone"), "!a")
        XCTAssertNil(RoomClosing.selection("!a", closing: "!a"))
        XCTAssertNil(RoomClosing.selection(nil, closing: "!a"))
    }

    // MARK: - Invite model

    func testAcceptRunsTheAcceptCallAndKeepsTheButtonsDisabled() async {
        let calls = CallCounter()
        let model = RoomInviteModel(accept: { calls.accepts += 1 }, reject: { calls.rejects += 1 })

        let succeeded = await model.perform(.accept)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(calls.accepts, 1)
        XCTAssertEqual(calls.rejects, 0)
        XCTAssertEqual(model.completed, .accept)
        XCTAssertNil(model.running)
        XCTAssertTrue(model.isBusy)
        XCTAssertTrue(model.showsProgress(for: .accept))
        XCTAssertFalse(model.showsProgress(for: .reject))
    }

    func testFailedRejectShowsTheErrorAndEnablesTheButtons() async {
        let model = RoomInviteModel(accept: {}, reject: { throw Refused() })

        let succeeded = await model.perform(.reject)

        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.failure?.action, .reject)
        XCTAssertEqual(model.failure?.detail, String(describing: Refused()))
        XCTAssertNil(model.completed)
        XCTAssertFalse(model.isBusy)
    }

    func testANewCallClearsTheLastError() async {
        let calls = CallCounter()
        let model = RoomInviteModel(
            accept: {
                calls.accepts += 1
                if calls.accepts == 1 { throw Refused() }
            },
            reject: {}
        )

        await model.perform(.accept)
        XCTAssertNotNil(model.failure)
        let succeeded = await model.perform(.accept)

        XCTAssertTrue(succeeded)
        XCTAssertNil(model.failure)
        XCTAssertEqual(calls.accepts, 2)
    }

    func testASecondCallWhileOneRunsDoesNotRun() async {
        let calls = CallCounter()
        let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
        let model = RoomInviteModel(
            accept: {
                for await _ in release {
                    break
                }
            },
            reject: { calls.rejects += 1 }
        )

        let first = Task { await model.perform(.accept) }
        for _ in 0 ..< 1000 where model.running == nil {
            await Task.yield()
        }
        XCTAssertEqual(model.running, .accept)
        XCTAssertTrue(model.isBusy)

        let second = await model.perform(.reject)
        releaseContinuation.yield()
        let firstSucceeded = await first.value

        XCTAssertFalse(second)
        XCTAssertEqual(calls.rejects, 0)
        XCTAssertTrue(firstSucceeded)
    }

    // MARK: - Invite details

    func testInviterNameComesFromTheInviteEvent() {
        let event = ChatListLatestEvent(
            timestamp: .now,
            sender: ChatListSender(userId: "@alex:example.org", displayName: "Alex", isOwn: false),
            content: .invite
        )

        XCTAssertEqual(RoomInviteDetails.inviterName(latestEvent: event), "Alex")
    }

    func testInviterNameFallsBackToTheLocalpart() {
        let event = ChatListLatestEvent(
            timestamp: .now,
            sender: ChatListSender(userId: "@alex:example.org", displayName: nil, isOwn: false),
            content: .invite
        )

        XCTAssertEqual(RoomInviteDetails.inviterName(latestEvent: event), "alex")
    }

    func testNoInviterNameWithoutAnInviteEvent() {
        let unknownInviter = ChatListLatestEvent(
            timestamp: .now,
            sender: ChatListSender(userId: "", displayName: nil, isOwn: false),
            content: .invite
        )
        let message = ChatListLatestEvent(
            timestamp: .now,
            sender: ChatListSender(userId: "@alex:example.org", displayName: "Alex", isOwn: false),
            content: .text("hi")
        )

        XCTAssertNil(RoomInviteDetails.inviterName(latestEvent: nil))
        XCTAssertNil(RoomInviteDetails.inviterName(latestEvent: unknownInviter))
        XCTAssertNil(RoomInviteDetails.inviterName(latestEvent: message))
    }

    // MARK: - Hosting

    /// The membership switch over `fixture`, with a fixture conversation as
    /// the joined screen and the real invite view on stub calls.
    private struct SwitchHost: View {
        let fixture: MembershipFixture
        let feed: TimelineFixtureFeed
        let log: ScreenLog

        var body: some View {
            NavigationStack {
                RoomMembershipSwitch(membership: fixture.membership, title: "Fixture room") {
                    TimelineFixtureConversation(feed: feed)
                } invited: {
                    RoomInviteView(
                        roomName: "Fixture room",
                        inviterName: "Alex",
                        model: RoomInviteModel(accept: {}, reject: {}),
                        onCompleted: { _ in }
                    )
                    .onAppear { log.events.append("invite") }
                }
            }
        }
    }

    /// A room detail that closes itself as soon as it shows.
    private struct ClosingDetail: View {
        @Environment(\.closeRoom) private var closeRoom
        let roomID: String
        let log: ScreenLog

        var body: some View {
            Color.clear
                .onAppear {
                    log.events.append("appear \(roomID)")
                    closeRoom?()
                }
                .onDisappear { log.events.append("disappear \(roomID)") }
        }
    }

    private func hostSwitch(_ fixture: MembershipFixture) -> ScreenLog {
        let log = ScreenLog()
        show(SwitchHost(fixture: fixture, feed: TimelineFixtureFeed(), log: log), usesStack: true)
        return log
    }

    private func hostShell(usesStack: Bool, openedRoomID: String) -> ScreenLog {
        let log = ScreenLog()
        let shell = RoomNavigationShell(
            rooms: SampleRoomListItem.all,
            isLoading: false,
            imageLoader: nil,
            usesStack: usesStack,
            openedRoomID: openedRoomID
        ) { room in
            ClosingDetail(roomID: room.id, log: log)
        }
        show(shell, usesStack: usesStack)
        return log
    }

    private func show(_ view: some View, usesStack: Bool) {
        let controller = UIHostingController(rootView: view)
        if !usesStack {
            // A regular-width window, so the split view shows its detail
            // column beside the sidebar.
            controller.traitOverrides.horizontalSizeClass = .regular
        }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            XCTFail("the test host has no window scene")
            return
        }
        let window = UIWindow(windowScene: scene)
        window.frame = usesStack ? CGRect(x: 0, y: 0, width: 390, height: 844) : CGRect(x: 0, y: 0, width: 1024, height: 768)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        addTeardownBlock { @MainActor in
            window.isHidden = true
        }
    }

    /// Runs the main run loop until `condition` holds, or the timeout passes.
    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date.now.addingTimeInterval(0.05))
        }
        return condition()
    }

    private func waitForTimeline(timeout: TimeInterval = 10) -> Bool {
        waitUntil(timeout: timeout) {
            window.map(Self.containsTimeline) ?? false
        }
    }

    private static func containsTimeline(_ view: UIView) -> Bool {
        if let collectionView = view as? UICollectionView, collectionView.collectionViewLayout is TimelineStackLayout {
            return true
        }
        return view.subviews.contains(where: containsTimeline)
    }
}

@testable import MactrixiOS
import Observation
import SwiftUI
import UIKit
import XCTest

/// MATRIX-245: a thread request pushes the thread screen onto the stack that
/// shows the room: over the room on iPhone, in the detail column beside the
/// room list on iPad. Nil pops it, back to the room.
///
/// The shell is hosted in a window with a fixture conversation as the room
/// detail, as `RoomNavigationTests` does. The thread screen is a probe view,
/// because the live one needs an SDK room. The probe counts as shown when its
/// UIKit view is in the window.
@MainActor
final class ThreadNavigationTests: XCTestCase {
    @Observable
    final class ThreadState {
        var request: ThreadScreenRequest?
    }

    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    func testThreadCoversTheRoomOnIPhone() throws {
        let state = ThreadState()
        try host(usesStack: true, state: state)
        XCTAssertTrue(waitUntil { Self.containsTimeline($0) }, "the room did not open")
        XCTAssertFalse(Self.containsProbe(window))

        state.request = .chip(rootEventId: "$root")

        XCTAssertTrue(waitUntil { Self.containsProbe($0) }, "the thread screen did not open")
        XCTAssertTrue(waitUntil { !Self.containsTimeline($0) }, "the thread screen did not cover the room")

        state.request = nil

        XCTAssertTrue(waitUntil { !Self.containsProbe($0) && Self.containsTimeline($0) }, "the back step did not show the room")
    }

    func testThreadShowsInTheDetailColumnOnIPad() throws {
        let state = ThreadState()
        try host(usesStack: false, state: state)
        XCTAssertTrue(waitUntil { Self.containsTimeline($0) }, "the room did not open")

        // "Reply in Thread" on a message of the room: no quote.
        state.request = ThreadScreenRequest(rootEventId: "$root", focusesComposer: true, quotedMessage: nil)

        XCTAssertTrue(waitUntil { Self.containsProbe($0) }, "the thread screen did not open")

        state.request = nil

        XCTAssertTrue(waitUntil { !Self.containsProbe($0) && Self.containsTimeline($0) }, "the back step did not show the room")
    }

    // MARK: - Hosting

    /// The room detail: the fixture conversation, with the thread
    /// destination that the live room screen has.
    private struct RoomDetail: View {
        @Bindable var state: ThreadState
        let feed: TimelineFixtureFeed

        var body: some View {
            TimelineFixtureConversation(feed: feed)
                .threadDestination($state.request) { _ in
                    ThreadProbe()
                }
        }
    }

    private func host(usesStack: Bool, state: ThreadState) throws {
        let feed = TimelineFixtureFeed()
        let shell = RoomNavigationShell(
            rooms: SampleRoomListItem.all,
            isLoading: false,
            imageLoader: nil,
            usesStack: usesStack,
            openedRoomID: "!dm1"
        ) { _ in
            RoomDetail(state: state, feed: feed)
        }

        let controller = UIHostingController(rootView: shell)
        if !usesStack {
            // The iPad idiom in a regular-width window, so the split view
            // shows its detail column beside the sidebar.
            controller.traitOverrides.horizontalSizeClass = .regular
        }
        let frame = usesStack ? CGRect(x: 0, y: 0, width: 390, height: 844) : CGRect(x: 0, y: 0, width: 1024, height: 768)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }

    /// Runs the main run loop until `condition` holds for the window, or the
    /// timeout passes.
    private func waitUntil(timeout: TimeInterval = 10, _ condition: (UIView) -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if let window, condition(window) { return true }
            RunLoop.main.run(until: Date.now.addingTimeInterval(0.05))
        }
        return window.map(condition) ?? false
    }

    private static func containsProbe(_ view: UIView?) -> Bool {
        guard let view else { return false }
        if view is ThreadProbe.ProbeView, view.window != nil { return true }
        return view.subviews.contains { containsProbe($0) }
    }

    private static func containsTimeline(_ view: UIView) -> Bool {
        if let collectionView = view as? UICollectionView, collectionView.collectionViewLayout is TimelineStackLayout {
            return true
        }
        return view.subviews.contains(where: containsTimeline)
    }
}

/// The thread screen's stand-in: a UIKit view the test finds in the window.
private struct ThreadProbe: UIViewRepresentable {
    final class ProbeView: UIView {}

    func makeUIView(context _: Context) -> ProbeView {
        ProbeView()
    }

    func updateUIView(_: ProbeView, context _: Context) {}
}

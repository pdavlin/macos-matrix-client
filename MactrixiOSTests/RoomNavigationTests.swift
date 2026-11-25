@testable import MactrixiOS
import SwiftUI
import UIKit
import XCTest

/// MATRIX-102: a selected room opens its timeline screen, not a placeholder.
///
/// The shell is hosted in a window with a fixture conversation as the room
/// detail, so no account or SDK room is needed. The timeline screen counts as
/// shown when the timeline container's collection view (the one on
/// `TimelineStackLayout`) is in the window. The room list is a collection
/// view too, so the layout class tells the two apart.
@MainActor
final class RoomNavigationTests: XCTestCase {
    private typealias Item = SampleRoomListItem

    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    func testSelectingARoomOnIPhoneShowsTheTimelineScreen() {
        let opened = host(usesStack: true, openedRoomID: "!dm1")

        XCTAssertTrue(waitForTimeline(), "the selected room did not show the timeline container")
        XCTAssertEqual(opened.ids, ["!dm1"])
    }

    func testSelectingARoomOnIPadShowsTheTimelineScreen() {
        let opened = host(usesStack: false, openedRoomID: "!room1")

        XCTAssertTrue(waitForTimeline(), "the selected room did not show the timeline container")
        XCTAssertEqual(opened.ids, ["!room1"])
    }

    func testNoSelectionShowsNoTimeline() {
        let opened = host(usesStack: true, openedRoomID: nil)

        XCTAssertFalse(waitForTimeline(timeout: 0.5))
        XCTAssertTrue(opened.ids.isEmpty)
    }

    func testDetailResolvesTheListedRoom() {
        let room = RoomDetailResolution.room(withID: "!dm2", in: Item.all, opened: nil)

        XCTAssertEqual(room?.id, "!dm2")
    }

    func testOpenRoomStaysOpenWhileTheListDropsIt() {
        let openedRoom = Item(id: "!dm2", title: "Sam (WhatsApp)", isDirect: true)

        let room = RoomDetailResolution.room(withID: "!dm2", in: [Item](), opened: openedRoom)

        XCTAssertEqual(room?.id, "!dm2")
    }

    func testUnknownRoomResolvesToThePlaceholder() {
        XCTAssertNil(RoomDetailResolution.room(withID: "!gone", in: Item.all, opened: nil))
        XCTAssertNil(RoomDetailResolution.room(withID: "!gone", in: Item.all, opened: Item.all[0]))
    }

    // MARK: Search results outside the list (MATRIX-247)

    func testSearchResultOutsideTheListOpensOnIPhone() {
        let outside = Item(id: "!old", title: "Book club")
        let opened = host(usesStack: true, openedRoomID: "!old") { $0 == outside.id ? outside : nil }

        XCTAssertTrue(waitForTimeline(), "a room outside the list did not show the timeline container")
        XCTAssertEqual(opened.ids, ["!old"])
    }

    func testSearchResultOutsideTheListOpensOnIPad() {
        let outside = Item(id: "!low", title: "Newsletters")
        let opened = host(usesStack: false, openedRoomID: "!low") { $0 == outside.id ? outside : nil }

        XCTAssertTrue(waitForTimeline(), "a room outside the list did not show the timeline container")
        XCTAssertEqual(opened.ids, ["!low"])
    }

    func testRoomTheLookUpCannotFindShowsNoTimeline() {
        let opened = host(usesStack: true, openedRoomID: "!gone") { _ in nil }

        XCTAssertFalse(waitForTimeline(timeout: 0.5))
        XCTAssertTrue(opened.ids.isEmpty)
    }

    // MARK: - Hosting

    /// The rooms the shell asked a detail for, in order.
    private final class OpenedRooms {
        var ids: [String] = []
    }

    private func host(
        usesStack: Bool,
        openedRoomID: String?,
        roomOutsideList: (@MainActor (String) -> Item?)? = nil
    ) -> OpenedRooms {
        let opened = OpenedRooms()
        let feed = TimelineFixtureFeed()
        let shell = RoomNavigationShell(
            rooms: Item.all,
            isLoading: false,
            imageLoader: nil,
            usesStack: usesStack,
            openedRoomID: openedRoomID,
            roomOutsideList: roomOutsideList
        ) { room in
            TimelineFixtureConversation(feed: feed)
                .onAppear { opened.ids.append(room.id) }
        }

        let controller = UIHostingController(rootView: shell)
        if !usesStack {
            // The iPad idiom in a regular-width window, so the split view
            // shows its detail column beside the sidebar.
            controller.traitOverrides.horizontalSizeClass = .regular
        }
        let frame = usesStack ? CGRect(x: 0, y: 0, width: 390, height: 844) : CGRect(x: 0, y: 0, width: 1024, height: 768)
        let window = makeWindow(frame: frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return opened
    }

    private func makeWindow(frame: CGRect) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return UIWindow(frame: frame) }
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        return window
    }

    /// Runs the main run loop until the timeline collection view is in the
    /// window, or the timeout passes.
    private func waitForTimeline(timeout: TimeInterval = 10) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if let window, Self.containsTimeline(window) { return true }
            RunLoop.main.run(until: Date.now.addingTimeInterval(0.05))
        }
        return window.map(Self.containsTimeline) ?? false
    }

    private static func containsTimeline(_ view: UIView) -> Bool {
        if let collectionView = view as? UICollectionView, collectionView.collectionViewLayout is TimelineStackLayout {
            return true
        }
        return view.subviews.contains(where: containsTimeline)
    }
}

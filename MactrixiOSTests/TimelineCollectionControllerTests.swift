@testable import MactrixiOS
import Models
import Tokens
import UIKit
import XCTest

/// MATRIX-85: the iOS container's row bookkeeping, driven by a scripted feed.
/// No window: the drain runs unpaced and nothing here depends on geometry.
@MainActor
final class TimelineCollectionControllerTests: XCTestCase {
    private final class ScriptedFeed: TimelineFeed {
        var displayRows: [TimelineRow] = []
        var pending: [TimelineRowChange] = []
        var typingNames: [String] = []
        var isPaginating = false
        var paginationFailure: String?
        var isAtBottom = true
        var unseenArrivals = 0
        var scrollToBottomRequests = 0
        var focusRequestId: String? { nil }

        func drainRowChanges() -> [TimelineRowChange] {
            defer { pending.removeAll() }
            return pending
        }

        func touchObservedState() {}
        func itemIndexOfFocusRequest() -> Int? {
            nil
        }

        func setAtBottom(_ atBottom: Bool) {
            isAtBottom = atBottom
        }

        func requestScrollToBottom() {
            scrollToBottomRequests += 1
        }

        func fetchOlderMessages() async {}
        func retryPagination() {}
    }

    private var minute: TimeInterval = 0

    private func message(from sender: String, body: String = "Hello") -> TimelineRow {
        minute += 60
        return TimelineFixtureEvent(
            sender: sender,
            name: sender,
            date: Date(timeIntervalSince1970: minute),
            body: body,
            reactionPills: []
        ).row
    }

    private func makeController(_ feed: ScriptedFeed) -> TimelineCollectionController {
        TimelineCollectionController(
            feed: feed,
            rowContext: TimelineRowContext(
                timeline: nil,
                imageLoader: nil,
                ownUserId: "@me:fixture",
                showsReadReceipts: false,
                typography: .default,
                retryPagination: {}
            )
        )
    }

    func testInitialRowsGroupBySender() {
        let feed = ScriptedFeed()
        // Newest first: two from Ada, then one from Bob.
        feed.displayRows = [message(from: "@ada"), message(from: "@ada"), message(from: "@bob")]

        let controller = makeController(feed)

        XCTAssertEqual(controller.rows.count, 3)
        XCTAssertFalse(controller.senderHeaders.contains(controller.rows[0].uniqueId))
        XCTAssertTrue(controller.senderHeaders.contains(controller.rows[1].uniqueId))
        XCTAssertTrue(controller.senderHeaders.contains(controller.rows[2].uniqueId))
        XCTAssertEqual(controller.snapshot.itemIdentifiers, controller.rows.map(\.uniqueId))
    }

    func testNewestEndInsertJoinsTheSenderRun() {
        let feed = ScriptedFeed()
        feed.displayRows = [message(from: "@ada")]
        let controller = makeController(feed)

        let arrival = message(from: "@ada")
        feed.pending = [TimelineRowChange(change: .insert(index: 0, count: 1), rows: [arrival])]
        controller.update()

        XCTAssertEqual(controller.rows.first?.uniqueId, arrival.uniqueId)
        XCTAssertFalse(controller.senderHeaders.contains(arrival.uniqueId))
        XCTAssertEqual(controller.snapshot.itemIdentifiers, controller.rows.map(\.uniqueId))
    }

    func testRemovingTheOlderNeighborOpensANewRun() {
        let feed = ScriptedFeed()
        let newest = message(from: "@ada")
        feed.displayRows = [newest, message(from: "@bob"), message(from: "@ada")]
        let controller = makeController(feed)
        XCTAssertTrue(controller.senderHeaders.contains(newest.uniqueId))

        feed.pending = [TimelineRowChange(change: .remove(index: 1, count: 1), rows: [])]
        controller.update()

        XCTAssertEqual(controller.rows.count, 2)
        XCTAssertFalse(controller.senderHeaders.contains(newest.uniqueId))
    }

    func testDecorationRowsSitAtTheirEnds() {
        let feed = ScriptedFeed()
        feed.displayRows = [message(from: "@ada"), message(from: "@bob")]
        let controller = makeController(feed)

        feed.typingNames = ["Bob"]
        feed.isPaginating = true
        controller.update()

        XCTAssertEqual(controller.leadingDecorationCount, 1)
        XCTAssertEqual(controller.trailingDecorationCount, 1)
        XCTAssertEqual(controller.rows.count, 4)
        XCTAssertEqual(controller.snapshot.itemIdentifiers, controller.rows.map(\.uniqueId))

        // An older batch lands before the pagination row, not after it.
        feed.isPaginating = false
        let older = message(from: "@cleo")
        feed.pending = [TimelineRowChange(change: .insert(index: 2, count: 1), rows: [older])]
        controller.update()

        XCTAssertEqual(controller.trailingDecorationCount, 0)
        XCTAssertEqual(controller.rows.last?.uniqueId, older.uniqueId)
        XCTAssertEqual(controller.snapshot.itemIdentifiers, controller.rows.map(\.uniqueId))
    }

    func testContentUpdateQueuesForTheDrain() {
        let feed = ScriptedFeed()
        let row = message(from: "@ada", body: "Before")
        feed.displayRows = [row]
        let controller = makeController(feed)

        guard case let .message(_, event, _, _) = row, let fixture = event as? TimelineFixtureEvent else {
            return XCTFail("fixture row expected")
        }
        let edited = fixture.with(body: "After").row
        feed.pending = [TimelineRowChange(change: .update(index: 0), rows: [edited])]
        controller.update()

        XCTAssertEqual(controller.pendingRowUpdates.count, 1)
    }

    func testDuplicateInsertRebuildsInsteadOfTrapping() {
        let feed = ScriptedFeed()
        let row = message(from: "@ada")
        feed.displayRows = [row]
        let controller = makeController(feed)

        // The feed reports an insert of a row the container already holds.
        feed.pending = [TimelineRowChange(change: .insert(index: 0, count: 1), rows: [row])]
        controller.update()

        XCTAssertEqual(controller.rows.map(\.uniqueId), [row.uniqueId])
        XCTAssertEqual(controller.snapshot.itemIdentifiers, [row.uniqueId])
    }
}

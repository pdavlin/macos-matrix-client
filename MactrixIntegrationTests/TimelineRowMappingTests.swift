import Foundation
@testable import Mactrix
import MatrixRustSDK
import Models
import XCTest

/// S-31: exercises the SDK `TimelineItem` → `Models.TimelineRow` mapping for
/// every item kind, including the previously-fatal path (an item that is
/// neither event nor virtual). All SDK types are constructed directly, and a
/// `TimelineItem` fake stands in for the Rust object (the SDK ships a
/// `noHandle` constructor exactly for this).
final class TimelineRowMappingTests: XCTestCase {
    // MARK: - Mapping behaviors

    func testMsgLikeContentMapsToMessageRow() {
        let item = makeMock(
            event: makeEvent(content: .msgLike(content: makeMsgLikeContent())),
            virtual: nil,
            uniqueId: "msg-1"
        )

        let row = item.row

        guard case let .message(uniqueId, event, kind, heightFingerprint) = row else {
            XCTFail("expected message row, got \(String(describing: row))")
            return
        }

        XCTAssertEqual(uniqueId, "msg-1")
        // A redacted body is neither text nor media, and the fake carries no
        // reactions, so the row lands in the plain "other" recycling pool.
        XCTAssertEqual(kind, .other)
        XCTAssertFalse(heightFingerprint.hasReactions)
        XCTAssertEqual(row.reuseId, "message.other")
        XCTAssertNotNil(event as? MatrixRustSDK.EventTimelineItem)
    }

    // MARK: - MATRIX-63: height fingerprint over real SDK content

    /// Mapping the same content twice has to produce equal fingerprints, or the
    /// skip rule never fires at all. The reaction-by-reaction rules are pinned
    /// in `TimelineRowHeightFingerprintTests`; this pins the SDK mapping that
    /// feeds them.
    func testMappingTheSameContentTwiceIsHeightNeutral() {
        let content: MatrixRustSDK.TimelineItemContent = .msgLike(content: makeMsgLikeContent())
        let first = makeMock(event: makeEvent(content: content), virtual: nil, uniqueId: "msg-1").row
        let second = makeMock(event: makeEvent(content: content), virtual: nil, uniqueId: "msg-1").row

        XCTAssertTrue(Models.TimelineRowHeightFingerprint.heightIsUnchanged(from: first, to: second))
    }

    /// The profile header draws the sender, and that line can wrap, so a sender
    /// change has to reach the fingerprint.
    func testSenderChangeIsNotHeightNeutral() {
        let content: MatrixRustSDK.TimelineItemContent = .msgLike(content: makeMsgLikeContent())
        let alice = makeMock(
            event: makeEvent(content: content, sender: "@alice:example.org"), virtual: nil, uniqueId: "msg-1"
        ).row
        let bob = makeMock(
            event: makeEvent(content: content, sender: "@bob:example.org"), virtual: nil, uniqueId: "msg-1"
        ).row

        XCTAssertFalse(Models.TimelineRowHeightFingerprint.heightIsUnchanged(from: alice, to: bob))
    }

    /// A state row carries no fingerprint, so it can never take the skip.
    func testStateRowIsNeverHeightNeutral() {
        let row = makeMock(event: makeEvent(content: .callInvite), virtual: nil, uniqueId: "state-3").row

        XCTAssertNil(row.heightFingerprint)
        XCTAssertFalse(Models.TimelineRowHeightFingerprint.heightIsUnchanged(from: row, to: row))
    }

    func testNonMessageContentKindsMapToStateRows() {
        let contents: [MatrixRustSDK.TimelineItemContent] = [
            .callInvite,
            .rtcNotification,
            .roomMembership(userId: "@bob:example.org", userDisplayName: "Bob", change: nil, reason: nil),
            .profileChange(displayName: "Bob", prevDisplayName: "Alice", avatarUrl: nil, prevAvatarUrl: nil),
            .state(stateKey: "m.room.name", content: .roomName(name: "Room")),
            .failedToParseMessageLike(eventType: "com.example", error: "nope"),
            .failedToParseState(eventType: "com.example", stateKey: "k", error: "nope"),
        ]

        for content in contents {
            let row = makeMock(event: makeEvent(content: content), virtual: nil, uniqueId: "state-1").row

            guard case let .state(uniqueId, _, name) = row else {
                XCTFail("expected state row for \(content), got \(String(describing: row))")
                return
            }

            XCTAssertEqual(uniqueId, "state-1")
            XCTAssertEqual(name, content.description)
        }
    }

    func testStateRowCarriesTheEvent() {
        let content: MatrixRustSDK.TimelineItemContent = .callInvite
        let row = makeMock(event: makeEvent(content: content), virtual: nil, uniqueId: "state-2").row

        guard case let .state(_, event, _) = row else {
            XCTFail("expected state row, got \(String(describing: row))")
            return
        }

        let carriedEvent = event as? MatrixRustSDK.EventTimelineItem
        XCTAssertNotNil(carriedEvent)
        XCTAssertEqual(carriedEvent?.sender, "@alice:example.org")
    }

    func testVirtualItemsMapToVirtualRows() {
        let dateDivider = makeMock(event: nil, virtual: .dateDivider(ts: 1_700_000_000_000), uniqueId: "d1")
        let readMarker = makeMock(event: nil, virtual: .readMarker, uniqueId: "r1")
        let timelineStart = makeMock(event: nil, virtual: .timelineStart, uniqueId: "s1")

        guard case let .virtual(uniqueId, .dateDivider(date)) = dateDivider.row else {
            XCTFail("expected dateDivider virtual row")
            return
        }
        XCTAssertEqual(uniqueId, "d1")
        XCTAssertEqual(date.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)

        guard case .virtual(_, .readMarker) = readMarker.row else {
            XCTFail("expected readMarker virtual row")
            return
        }
        XCTAssertEqual(readMarker.row.reuseId, "virtual.readMarker")

        guard case .virtual(_, .timelineStart) = timelineStart.row else {
            XCTFail("expected timelineStart virtual row")
            return
        }
    }

    /// S-34: an item that is neither event nor virtual maps to `.unsupported`
    /// rather than being dropped. The container mirrors the SDK diff by index,
    /// so a dropped item would shift every later row out from under the
    /// indices the diff carries.
    func testItemThatIsNeitherEventNorVirtualMapsToUnsupported() {
        // Previously hit `fatalError("unreachable state: item must be either virtual or event")`.
        let item = makeMock(event: nil, virtual: nil, uniqueId: "neither")

        guard case let .unsupported(uniqueId) = item.row else {
            XCTFail("expected unsupported row, got \(item.row)")
            return
        }
        XCTAssertEqual(uniqueId, "neither")
        XCTAssertEqual(item.row.reuseId, "unsupported")
    }

    func testUniqueIdFlowsThroughEveryKind() {
        let message = makeMock(
            event: makeEvent(content: .msgLike(content: makeMsgLikeContent())), virtual: nil, uniqueId: "u-message"
        )
        let state = makeMock(event: makeEvent(content: .callInvite), virtual: nil, uniqueId: "u-state")
        let virtual = makeMock(event: nil, virtual: .readMarker, uniqueId: "u-virtual")

        XCTAssertEqual(message.row.uniqueId, "u-message")
        XCTAssertEqual(state.row.uniqueId, "u-state")
        XCTAssertEqual(virtual.row.uniqueId, "u-virtual")
    }

    // MARK: - Helpers

    private func makeMock(
        event: MatrixRustSDK.EventTimelineItem?,
        virtual: MatrixRustSDK.VirtualTimelineItem?,
        uniqueId: String
    ) -> MockTimelineItem {
        MockTimelineItem(event: event, virtual: virtual, uniqueId: uniqueId)
    }

    private func makeEvent(
        content: MatrixRustSDK.TimelineItemContent,
        sender: String = "@alice:example.org"
    ) -> MatrixRustSDK.EventTimelineItem {
        MatrixRustSDK.EventTimelineItem(
            isRemote: true,
            eventOrTransactionId: .eventId(eventId: "event-id"),
            sender: sender,
            senderProfile: .unavailable,
            forwarder: nil,
            forwarderProfile: nil,
            isOwn: false,
            isEditable: false,
            content: content,
            timestamp: 1_700_000_000_000,
            localSendState: nil,
            localCreatedAt: nil,
            readReceipts: [:],
            origin: nil,
            canBeRepliedTo: true,
            lazyProvider: MatrixRustSDK.LazyTimelineItemProvider(noHandle: .init())
        )
    }

    private func makeMsgLikeContent() -> MatrixRustSDK.MsgLikeContent {
        MatrixRustSDK.MsgLikeContent(
            kind: .redacted,
            reactions: [],
            inReplyTo: nil,
            threadRoot: nil,
            threadSummary: nil
        )
    }
}

/// Fake `TimelineItem` whose `asEvent()`/`asVirtual()`/`uniqueId()` return
/// injected values, so the mapping is testable without a Rust handle. The SDK
/// exposes `init(noHandle:)` precisely for this purpose.
private final class MockTimelineItem: MatrixRustSDK.TimelineItem {
    private let event: MatrixRustSDK.EventTimelineItem?
    private let virtual: MatrixRustSDK.VirtualTimelineItem?
    private let uniqueID: MatrixRustSDK.TimelineUniqueId

    init(
        event: MatrixRustSDK.EventTimelineItem?,
        virtual: MatrixRustSDK.VirtualTimelineItem?,
        uniqueId: String
    ) {
        self.event = event
        self.virtual = virtual
        self.uniqueID = MatrixRustSDK.TimelineUniqueId(id: uniqueId)
        super.init(noHandle: MatrixRustSDK.TimelineItem.NoHandle())
    }

    override func asEvent() -> MatrixRustSDK.EventTimelineItem? {
        event
    }

    override func asVirtual() -> MatrixRustSDK.VirtualTimelineItem? {
        virtual
    }

    override func uniqueId() -> MatrixRustSDK.TimelineUniqueId {
        uniqueID
    }

    @available(*, unavailable)
    required init(unsafeFromHandle _: UInt64) {
        fatalError("MockTimelineItem must be created with init(event:virtual:uniqueId:)")
    }
}

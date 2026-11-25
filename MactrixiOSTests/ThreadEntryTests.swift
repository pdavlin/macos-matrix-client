@testable import MactrixiOS
import Models
import XCTest

/// MATRIX-245, MATRIX-246: the iOS thread entry points. The long-press menu
/// takes its reply entries from the shared action model, "Reply in Thread"
/// pushes the thread screen from the room timeline and replies in place in
/// the thread screen, and the composer sends through the shared reply route.
final class ThreadEntryTests: XCTestCase {
    private func subject(
        repliesInThreads: Bool,
        canBeRepliedTo: Bool = true,
        content: MessageActionSubject.Content = .text
    ) -> MessageActionSubject {
        MessageActionSubject(
            content: content,
            isOwn: false,
            eventId: "$message",
            canBeRepliedTo: canBeRepliedTo,
            isPinned: false,
            copyableText: "hello",
            repliesInThreads: repliesInThreads
        )
    }

    // MARK: - Long-press menu

    /// A phone has no hover row: the room timeline's menu offers both
    /// entries, so a thread is reachable in every room.
    func testRoomTimelineMenuOffersReplyAndReplyInThread() {
        XCTAssertEqual(TimelineReplyMenu.actions(for: subject(repliesInThreads: false), inThread: false), [.reply, .replyInThread])
    }

    /// MATRIX-246: a Slack room has no inline reply, as on the Mac.
    func testSlackRoomMenuOffersReplyInThreadOnly() {
        XCTAssertEqual(TimelineReplyMenu.actions(for: subject(repliesInThreads: true), inThread: false), [.replyInThread])
    }

    func testThreadScreenMenuOffersOneReplyEntry() {
        XCTAssertEqual(TimelineReplyMenu.actions(for: subject(repliesInThreads: false), inThread: true), [.reply])
        XCTAssertEqual(TimelineReplyMenu.actions(for: subject(repliesInThreads: true), inThread: true), [.replyInThread])
    }

    /// A local echo cannot take a reply yet, and a redacted message never.
    func testMessageThatCannotTakeAReplyOffersNoReplyEntry() {
        XCTAssertEqual(TimelineReplyMenu.actions(for: subject(repliesInThreads: false, canBeRepliedTo: false), inThread: false), [])
        XCTAssertEqual(TimelineReplyMenu.actions(for: subject(repliesInThreads: true, content: .redacted), inThread: false), [])
    }

    // MARK: - Reply in Thread

    func testReplyInThreadOnARoomMessageOpensItsOwnThread() {
        let entry = ThreadReplyEntry.of(eventId: "$message", messageThreadRoot: nil, timelineThreadRoot: nil)

        XCTAssertEqual(entry, .openThread(ThreadReplyStart(root: "$message", quotedEventId: nil)))
    }

    /// Matrix threads do not nest: a message inside a thread gets its reply
    /// inside that thread, as a reply to the message.
    func testReplyInThreadOnAThreadMessageOpensThatThreadAndQuotesIt() {
        let entry = ThreadReplyEntry.of(eventId: "$reply", messageThreadRoot: "$root", timelineThreadRoot: nil)

        XCTAssertEqual(entry, .openThread(ThreadReplyStart(root: "$root", quotedEventId: "$reply")))
    }

    func testReplyInThreadOnTheThreadScreenRootRepliesInPlaceWithNoQuote() {
        let entry = ThreadReplyEntry.of(eventId: "$root", messageThreadRoot: nil, timelineThreadRoot: "$root")

        XCTAssertEqual(entry, .replyHere(quotesMessage: false))
    }

    func testReplyInThreadOnAThreadScreenReplyQuotesItInPlace() {
        let entry = ThreadReplyEntry.of(eventId: "$reply", messageThreadRoot: "$root", timelineThreadRoot: "$root")

        XCTAssertEqual(entry, .replyHere(quotesMessage: true))
    }

    func testChipOpensTheThreadWithNoComposerFocus() {
        let request = ThreadScreenRequest.chip(rootEventId: "$root")

        XCTAssertEqual(request.id, "$root")
        XCTAssertFalse(request.focusesComposer)
        XCTAssertNil(request.quotedMessage)
    }

    // MARK: - Composer route (MATRIX-246)

    /// The route of a reply from an iOS composer: the inputs that
    /// `LiveComposerTarget` gives the shared `LiveTimeline.send`.
    private func route(
        composerThreadRoot: String? = nil,
        target: String = "$message",
        targetThreadRoot: String? = nil,
        targetIsThreadRoot: Bool = false,
        network: ChatListNetwork?
    ) -> ReplyRoute {
        ReplyRoute.route(
            composerThreadRoot: composerThreadRoot,
            openThreadRoot: LiveComposerTarget.openThreadRoot,
            targetEventId: target,
            targetThreadRoot: targetThreadRoot,
            targetHasThreadSummary: targetIsThreadRoot,
            repliesInThreads: ThreadedReplyRule.repliesInThreads(on: network)
        )
    }

    /// The thread screen covers the room, so no thread is open beside the
    /// room composer.
    func testComposerGivesNoOpenThreadRoot() {
        XCTAssertNil(LiveComposerTarget.openThreadRoot)
    }

    func testSlackReplyFromTheRoomComposerGoesIntoTheTargetsThread() {
        let reply = route(network: .slack)

        XCTAssertEqual(reply, .thread(root: "$message", inReplyTo: nil))
        XCTAssertEqual(ReplyRoute.sendTimeline(for: reply, composerThreadRoot: nil), .thread(root: "$message"))
    }

    func testOtherRoomsKeepThePlainReply() {
        XCTAssertEqual(route(network: .whatsApp), .plain(inReplyTo: "$message"))
        XCTAssertEqual(route(network: nil), .plain(inReplyTo: "$message"))
    }

    /// The thread chip shows the replies now, so a reply to a root joins
    /// its thread, as on the Mac (MATRIX-169).
    func testReplyToAThreadRootFromTheRoomComposerJoinsTheThread() {
        XCTAssertEqual(route(targetIsThreadRoot: true, network: nil), .thread(root: "$message", inReplyTo: nil))
    }

    func testThreadComposerSendsIntoItsThread() {
        let quoting = route(composerThreadRoot: "$root", target: "$reply", targetThreadRoot: "$root", network: nil)
        let toRoot = route(composerThreadRoot: "$root", target: "$root", network: .slack)

        XCTAssertEqual(quoting, .thread(root: "$root", inReplyTo: "$reply"))
        XCTAssertEqual(toRoot, .thread(root: "$root", inReplyTo: nil))
        XCTAssertEqual(ReplyRoute.sendTimeline(for: quoting, composerThreadRoot: "$root"), .composer)
    }
}

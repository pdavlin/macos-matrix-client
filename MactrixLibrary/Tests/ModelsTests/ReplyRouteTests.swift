@testable import Models
import Testing

/// MATRIX-169: where a reply from the composer goes.
struct ReplyRouteTests {
    private static let root = "$root"
    private static let inThread = "$inThread"
    private static let plain = "$plain"

    // MARK: Main timeline

    @Test
    func replyToPlainMessageStaysPlain() {
        let route = ReplyRoute.route(
            composerThreadRoot: nil,
            targetEventId: Self.plain,
            targetThreadRoot: nil,
            targetHasThreadSummary: false
        )
        #expect(route == .plain(inReplyTo: Self.plain))
        #expect(route.threadRoot == nil)
        #expect(route.inReplyTo == Self.plain)
    }

    @Test
    func replyToThreadRootGoesIntoItsThreadWithNoQuote() {
        let route = ReplyRoute.route(
            composerThreadRoot: nil,
            targetEventId: Self.root,
            targetThreadRoot: nil,
            targetHasThreadSummary: true
        )
        #expect(route == .thread(root: Self.root, inReplyTo: nil))
        #expect(route.threadRoot == Self.root)
        #expect(route.inReplyTo == nil)
    }

    @Test
    func replyToMessageInsideThreadGoesIntoThatThread() {
        let route = ReplyRoute.route(
            composerThreadRoot: nil,
            targetEventId: Self.inThread,
            targetThreadRoot: Self.root,
            targetHasThreadSummary: false
        )
        #expect(route == .thread(root: Self.root, inReplyTo: Self.inThread))
    }

    /// The thread of the target wins over a summary on the target: the SDK
    /// gives no summary to a message inside a thread, and a thread does not
    /// nest.
    @Test
    func targetThreadWinsOverTargetSummary() {
        let route = ReplyRoute.route(
            composerThreadRoot: nil,
            targetEventId: Self.inThread,
            targetThreadRoot: Self.root,
            targetHasThreadSummary: true
        )
        #expect(route == .thread(root: Self.root, inReplyTo: Self.inThread))
    }

    // MARK: Thread panel

    @Test
    func replyFromThreadPanelGoesIntoThatThread() {
        let route = ReplyRoute.route(
            composerThreadRoot: Self.root,
            targetEventId: Self.inThread,
            targetThreadRoot: Self.root,
            targetHasThreadSummary: false
        )
        #expect(route == .thread(root: Self.root, inReplyTo: Self.inThread))
    }

    @Test
    func replyToTheRootFromThreadPanelHasNoQuote() {
        let route = ReplyRoute.route(
            composerThreadRoot: Self.root,
            targetEventId: Self.root,
            targetThreadRoot: nil,
            targetHasThreadSummary: true
        )
        #expect(route == .thread(root: Self.root, inReplyTo: nil))
    }

    /// The panel shows the root before the thread has a reply ("Reply in
    /// Thread" on a plain message). A reply there starts the thread.
    @Test
    func replyToRootWithNoSummaryFromThreadPanelGoesIntoThePanelThread() {
        let route = ReplyRoute.route(
            composerThreadRoot: Self.root,
            targetEventId: Self.root,
            targetThreadRoot: nil,
            targetHasThreadSummary: false
        )
        #expect(route == .thread(root: Self.root, inReplyTo: nil))
    }

    @Test
    func threadPanelWinsOverTargetThread() {
        let route = ReplyRoute.route(
            composerThreadRoot: Self.root,
            targetEventId: Self.inThread,
            targetThreadRoot: "$other",
            targetHasThreadSummary: false
        )
        #expect(route.threadRoot == Self.root)
    }
}

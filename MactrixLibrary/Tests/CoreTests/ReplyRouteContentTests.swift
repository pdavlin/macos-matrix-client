@testable import Core
import MatrixRustSDK
import Models
import Testing

/// MATRIX-216: the route of a reply to a message with no thread yet, read
/// from SDK content. A text root and an image root (with a caption) take the
/// same route: the content kind has no part in it.
struct ReplyRouteContentTests {
    private static let root = "$root"

    private static func content(_ msgType: MatrixRustSDK.MessageType, body: String) -> MatrixRustSDK.TimelineItemContent {
        .msgLike(content: MatrixRustSDK.MsgLikeContent(
            kind: .message(content: MatrixRustSDK.MessageContent(msgType: msgType, body: body, isEdited: false, mentions: nil)),
            inReplyTo: nil,
            threadRoot: nil,
            threadSummary: nil
        ))
    }

    private static func text() -> MatrixRustSDK.TimelineItemContent {
        content(.text(content: TextMessageContent(body: "hello", formatted: nil)), body: "hello")
    }

    private static func image() throws -> MatrixRustSDK.TimelineItemContent {
        let source = try MediaSource.fromUrl(url: "mxc://example.org/garden")
        let image = ImageMessageContent(
            filename: "garden.jpg",
            caption: "the new bed",
            formattedCaption: nil,
            source: source,
            info: nil
        )
        return content(.image(content: image), body: "the new bed")
    }

    private static func roots() throws -> [MatrixRustSDK.TimelineItemContent] {
        try [text(), image()]
    }

    /// The main composer, no thread panel: a plain reply, as before.
    @Test
    func mainComposerWithNoPanelRepliesPlain() throws {
        for root in try Self.roots() {
            let route = ReplyRoute.route(composerThreadRoot: nil, openThreadRoot: nil, targetEventId: Self.root, targetContent: root)
            #expect(route == .plain(inReplyTo: Self.root))
            #expect(ReplyRoute.sendTimeline(for: route, composerThreadRoot: nil) == .composer)
        }
    }

    /// The main composer while the panel shows the root's new thread: the
    /// reply goes through a timeline with the focus on that thread.
    @Test
    func mainComposerWithThePanelOnTheRootSendsThroughTheThread() throws {
        for root in try Self.roots() {
            let route = ReplyRoute.route(
                composerThreadRoot: nil,
                openThreadRoot: Self.root,
                targetEventId: Self.root,
                targetContent: root
            )
            #expect(route == .thread(root: Self.root, inReplyTo: nil))
            #expect(ReplyRoute.sendTimeline(for: route, composerThreadRoot: nil) == .thread(root: Self.root))
        }
    }

    /// The thread panel's composer ("Reply in Thread", then a reply to the
    /// root): the panel's own thread timeline sends it.
    @Test
    func panelComposerSendsThroughItsThreadTimeline() throws {
        for root in try Self.roots() {
            let route = ReplyRoute.route(
                composerThreadRoot: Self.root,
                openThreadRoot: Self.root,
                targetEventId: Self.root,
                targetContent: root
            )
            #expect(route == .thread(root: Self.root, inReplyTo: nil))
            #expect(ReplyRoute.sendTimeline(for: route, composerThreadRoot: Self.root) == .composer)
        }
    }
}

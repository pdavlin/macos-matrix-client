import Models
import Testing

/// MATRIX-232: in a room of a network that puts every reply in a thread
/// (Slack), every Reply entry point acts as Reply in Thread, and no reply
/// from a main timeline is plain.
struct ThreadedReplyRuleTests {
    private static let reactions: [MessageAction] = MessageActionModel.defaultQuickReactionKeys.map { .toggleReaction(key: $0) }

    private func subject(repliesInThreads: Bool, isInMergedChat: Bool = false) -> MessageActionSubject {
        MessageActionSubject(
            content: .text,
            isOwn: false,
            eventId: "$event",
            canBeRepliedTo: true,
            isPinned: false,
            copyableText: "hello",
            isInMergedChat: isInMergedChat,
            repliesInThreads: repliesInThreads
        )
    }

    private func actions(_ subject: MessageActionSubject?, on surface: MessageActionSurface) -> [MessageAction] {
        MessageActionModel.items(for: subject, on: surface).map(\.action)
    }

    private func replyActions(_ subject: MessageActionSubject?, on surface: MessageActionSurface) -> [MessageAction] {
        actions(subject, on: surface).filter { $0 == .reply || $0 == .replyInThread }
    }

    // MARK: The network rule

    @Test func slackPutsRepliesInThreads() {
        #expect(ThreadedReplyRule.repliesInThreads(on: .slack))
    }

    @Test func otherNetworksAndPlainRoomsKeepTheInlineReply() {
        #expect(!ThreadedReplyRule.repliesInThreads(on: nil))
        for network in ChatListNetwork.allCases where network != .slack {
            #expect(!ThreadedReplyRule.repliesInThreads(on: network), "\(network)")
        }
    }

    // MARK: The surfaces

    @Test func everySurfaceOffersReplyInThreadOnceAndNoInlineReply() {
        let slack = subject(repliesInThreads: true)
        for surface in MessageActionSurface.allCases {
            #expect(replyActions(slack, on: surface) == [.replyInThread], "\(surface)")
        }
    }

    @Test func replyInThreadTakesThePlaceOfReply() {
        let slack = subject(repliesInThreads: true)
        let contextMenu: [MessageAction] = [.replyInThread] + Self.reactions + [.openReactionPicker, .copyText, .copyLink, .pin, .bookmark]
        #expect(actions(slack, on: .contextMenu) == contextMenu)
        #expect(actions(slack, on: .hoverRow) == Self.reactions + [.openReactionPicker, .replyInThread, .pin])
        #expect(actions(slack, on: .editMenu).first == .replyInThread)
        #expect(MessageActionModel.items(for: slack, on: .editMenu).first?.isEnabled == true)
    }

    @Test func otherRoomsKeepReply() {
        let room = subject(repliesInThreads: false)
        #expect(replyActions(room, on: .contextMenu) == [.reply])
        #expect(replyActions(room, on: .editMenu) == [.reply])
        #expect(replyActions(room, on: .hoverRow) == [.reply, .replyInThread])
        #expect(replyActions(nil, on: .editMenu) == [.reply])
    }

    /// The Edit menu keeps one shape: Reply in Thread stands where Reply
    /// stands for other rooms.
    @Test func editMenuKeepsItsLength() {
        let slack = actions(subject(repliesInThreads: true), on: .editMenu)
        let room = actions(subject(repliesInThreads: false), on: .editMenu)
        #expect(slack.count == room.count)
        #expect(Array(slack.dropFirst()) == Array(room.dropFirst()))
    }

    /// A merged chat has no thread panel, but a Slack message keeps one
    /// reply item there: Reply in Thread. The other members keep Reply.
    @Test func mergedChatKeepsReplyInThreadForASlackMessage() {
        let slack = subject(repliesInThreads: true, isInMergedChat: true)
        for surface in MessageActionSurface.allCases {
            #expect(replyActions(slack, on: surface) == [.replyInThread], "\(surface)")
        }
        #expect(MessageActionModel.items(for: slack, on: .contextMenu).first { $0.action == .replyInThread }?.isEnabled == true)
        let other = subject(repliesInThreads: false, isInMergedChat: true)
        #expect(replyActions(other, on: .hoverRow) == [.reply])
        #expect(replyActions(other, on: .contextMenu) == [.reply])
    }

    @Test func aLocalEchoShowsReplyInThreadDisabledInTheMenu() {
        var echo = subject(repliesInThreads: true)
        echo.eventId = nil
        echo.canBeRepliedTo = false
        #expect(MessageActionModel.items(for: echo, on: .contextMenu).first { $0.action == .replyInThread }?.isEnabled == false)
        #expect(!actions(echo, on: .hoverRow).contains(.replyInThread))
    }

    // MARK: The send route

    @Test func aReplyToAPlainMessageStartsItsThread() {
        let route = ReplyRoute.route(
            composerThreadRoot: nil,
            targetEventId: "$plain",
            targetThreadRoot: nil,
            targetHasThreadSummary: false,
            repliesInThreads: true
        )
        #expect(route == .thread(root: "$plain", inReplyTo: nil))
        #expect(ReplyRoute.sendTimeline(for: route, composerThreadRoot: nil) == .thread(root: "$plain"))
    }

    @Test func threadRoutesDoNotChange() {
        let inThread = ReplyRoute.route(
            composerThreadRoot: nil,
            targetEventId: "$reply",
            targetThreadRoot: "$root",
            targetHasThreadSummary: false,
            repliesInThreads: true
        )
        #expect(inThread == .thread(root: "$root", inReplyTo: "$reply"))
        let panel = ReplyRoute.route(
            composerThreadRoot: "$root",
            targetEventId: "$reply",
            targetThreadRoot: "$root",
            targetHasThreadSummary: false,
            repliesInThreads: true
        )
        #expect(panel == .thread(root: "$root", inReplyTo: "$reply"))
    }

    @Test func otherRoomsKeepThePlainReply() {
        let route = ReplyRoute.route(
            composerThreadRoot: nil,
            targetEventId: "$plain",
            targetThreadRoot: nil,
            targetHasThreadSummary: false,
            repliesInThreads: false
        )
        #expect(route == .plain(inReplyTo: "$plain"))
    }

    // MARK: Where Reply in Thread goes

    @Test func aMessageOutsideAThreadStartsItsOwnThread() {
        #expect(ThreadReplyStart.of(eventId: "$plain", threadRoot: nil) == ThreadReplyStart(root: "$plain", quotedEventId: nil))
    }

    @Test func aThreadRootGetsAPlainThreadMessage() {
        #expect(ThreadReplyStart.of(eventId: "$root", threadRoot: "$root") == ThreadReplyStart(root: "$root", quotedEventId: nil))
    }

    @Test func aMessageInsideAThreadGetsAReplyInsideThatThread() {
        #expect(ThreadReplyStart.of(eventId: "$reply", threadRoot: "$root") == ThreadReplyStart(root: "$root", quotedEventId: "$reply"))
    }
}

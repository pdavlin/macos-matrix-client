import Models
import Testing

/// MATRIX-143 (M2.5-4): which member room each merged-chat action goes to.
struct MergedChatRoutingTests {
    private static let roomA = "!a:davlin.io"
    private static let roomB = "!b:davlin.io"
    private static let rooms = [roomA, roomB]
    private static let autoTarget = MergedSendTarget(roomId: roomA, reason: .recentActivity)

    /// Every action, one value of each case.
    private static let allActions: [MessageAction] = [
        .reply, .replyInThread, .toggleReaction(key: "👍"), .openReactionPicker, .edit, .forward,
        .copyText, .copyLink, .pin, .unpin, .quickLook, .playInline, .saveToDownloads, .redact, .copyMessages,
    ]

    // MARK: - Message actions

    @Test(arguments: allActions.filter { $0 != .copyMessages })
    func eventActionsRunInTheEventsRoom(action: MessageAction) {
        #expect(MergedChatRouting.route(for: action, eventRoomId: Self.roomB, rooms: Self.rooms) == .room(Self.roomB))
    }

    @Test(arguments: allActions.filter { $0 != .copyMessages })
    func eventActionsInARoomOutsideTheMergeDoNothing(action: MessageAction) {
        let route = MergedChatRouting.route(for: action, eventRoomId: "!gone:davlin.io", rooms: Self.rooms)
        #expect(route == .notAMember)
    }

    @Test func copyMessagesNeedsNoRoom() {
        #expect(MergedChatRouting.route(for: .copyMessages, eventRoomId: Self.roomB, rooms: Self.rooms) == .noRoom)
    }

    @Test func eventActionsIgnoreTheSendTarget() {
        // The send target is A; a reaction on B's event still goes to B.
        let route = MergedChatRouting.route(for: .toggleReaction(key: "❤️"), eventRoomId: Self.roomB, rooms: Self.rooms)
        #expect(route == .room(Self.roomB))
    }

    // MARK: - Composer target

    @Test func newMessageUsesTheSendTarget() {
        let target = MergedChatRouting.composerTarget(for: .newMessage, autoTarget: Self.autoTarget, rooms: Self.rooms)
        #expect(target == Self.autoTarget)
    }

    @Test func replyGoesToTheRepliedEventsRoom() {
        let target = MergedChatRouting.composerTarget(
            for: .reply(eventRoomId: Self.roomB),
            autoTarget: Self.autoTarget,
            rooms: Self.rooms
        )
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .reply))
    }

    @Test func replyOverridesAManualPick() {
        let chosen = MergedSendTarget(roomId: Self.roomA, reason: .chosen)
        let target = MergedChatRouting.composerTarget(
            for: .reply(eventRoomId: Self.roomB),
            autoTarget: chosen,
            rooms: Self.rooms
        )
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .reply))
    }

    @Test func editGoesToTheEditedEventsRoom() {
        let target = MergedChatRouting.composerTarget(
            for: .edit(eventRoomId: Self.roomB),
            autoTarget: Self.autoTarget,
            rooms: Self.rooms
        )
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .edit))
    }

    @Test func replyToARoomOutsideTheMergeFallsBackToTheSendTarget() {
        let target = MergedChatRouting.composerTarget(
            for: .reply(eventRoomId: "!gone:davlin.io"),
            autoTarget: Self.autoTarget,
            rooms: Self.rooms
        )
        #expect(target == Self.autoTarget)
    }

    @Test func editInARoomOutsideTheMergeFallsBackToTheSendTarget() {
        let target = MergedChatRouting.composerTarget(
            for: .edit(eventRoomId: "!gone:davlin.io"),
            autoTarget: Self.autoTarget,
            rooms: Self.rooms
        )
        #expect(target == Self.autoTarget)
    }

    // MARK: - Typing

    @Test func startTypingNotifiesTheTargetOnly() {
        let notices = MergedChatRouting.typingNotices(previousRoom: nil, currentRoom: Self.roomA, isTyping: true)
        #expect(notices == [.init(roomId: Self.roomA, isTyping: true)])
    }

    @Test func continuedTypingInTheSameRoomSendsNothing() {
        #expect(MergedChatRouting.typingNotices(previousRoom: Self.roomA, currentRoom: Self.roomA, isTyping: true).isEmpty)
    }

    @Test func stopTypingClearsThePreviousRoom() {
        let notices = MergedChatRouting.typingNotices(previousRoom: Self.roomA, currentRoom: Self.roomA, isTyping: false)
        #expect(notices == [.init(roomId: Self.roomA, isTyping: false)])
    }

    @Test func targetChangeWhileTypingMovesTheNotice() {
        let notices = MergedChatRouting.typingNotices(previousRoom: Self.roomA, currentRoom: Self.roomB, isTyping: true)
        #expect(notices == [.init(roomId: Self.roomA, isTyping: false), .init(roomId: Self.roomB, isTyping: true)])
    }

    @Test func targetChangeWhileIdleSendsNothing() {
        #expect(MergedChatRouting.typingNotices(previousRoom: nil, currentRoom: Self.roomB, isTyping: false).isEmpty)
    }

    @Test func lostTargetClearsThePreviousRoom() {
        let notices = MergedChatRouting.typingNotices(previousRoom: Self.roomA, currentRoom: nil, isTyping: true)
        #expect(notices == [.init(roomId: Self.roomA, isTyping: false)])
    }

    // MARK: - Read receipts

    @Test func eachRoomGetsItsNewestVisibleEvent() {
        let receipts = MergedChatRouting.readReceipts(
            newestVisibleEvents: [Self.roomB: "$b2", Self.roomA: "$a9"],
            rooms: Self.rooms
        )
        #expect(receipts == [.init(roomId: Self.roomA, eventId: "$a9"), .init(roomId: Self.roomB, eventId: "$b2")])
    }

    @Test func roomWithNoVisibleEventGetsNoReceipt() {
        let receipts = MergedChatRouting.readReceipts(newestVisibleEvents: [Self.roomB: "$b2"], rooms: Self.rooms)
        #expect(receipts == [.init(roomId: Self.roomB, eventId: "$b2")])
    }

    @Test func receiptAlreadySentIsNotSentAgain() {
        let receipts = MergedChatRouting.readReceipts(
            newestVisibleEvents: [Self.roomA: "$a9", Self.roomB: "$b3"],
            alreadySent: [Self.roomA: "$a9", Self.roomB: "$b2"],
            rooms: Self.rooms
        )
        #expect(receipts == [.init(roomId: Self.roomB, eventId: "$b3")])
    }

    @Test func receiptsForNonMembersAreDropped() {
        let receipts = MergedChatRouting.readReceipts(
            newestVisibleEvents: ["!gone:davlin.io": "$x", Self.roomA: "$a1"],
            rooms: Self.rooms
        )
        #expect(receipts == [.init(roomId: Self.roomA, eventId: "$a1")])
    }

    @Test func nothingVisibleSendsNoReceipts() {
        #expect(MergedChatRouting.readReceipts(newestVisibleEvents: [:], rooms: Self.rooms).isEmpty)
    }
}

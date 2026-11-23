import Foundation
import Models
import Testing

/// A fake SDK layer for the notification actions: it records each call.
@MainActor
private final class FakePerformer: NotificationActionPerformer {
    enum Call: Equatable {
        case send(text: String, roomId: String, threadRoot: String?)
        case markAsRead([String])
        case remind([String], Date)
        case removeDelivered([String])
    }

    private(set) var calls: [Call] = []

    func sendReply(_ text: String, toRoom roomId: String, threadRoot: String?) async {
        calls.append(.send(text: text, roomId: roomId, threadRoot: threadRoot))
    }

    func markAsRead(roomIds: [String]) async {
        calls.append(.markAsRead(roomIds))
    }

    func remind(roomIds: [String], at date: Date) async {
        calls.append(.remind(roomIds, date))
    }

    func removeDeliveredNotifications(roomIds: [String]) async {
        calls.append(.removeDelivered(roomIds))
    }
}

/// MATRIX-221: the notification actions, from the response's identifier
/// to the SDK calls.
@MainActor
struct NotificationActionTests {
    private let defaultIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!slack", "!groupme"])

    private func action(_ identifier: String, text: String? = nil) -> NotificationAction? {
        NotificationAction(identifier: identifier, defaultIdentifier: defaultIdentifier, userText: text)
    }

    private func perform(
        _ action: NotificationAction,
        on target: NotificationTarget,
        merges: [MergedChat] = []
    ) async -> [FakePerformer.Call] {
        let performer = FakePerformer()
        await NotificationActionRouter.perform(
            action,
            on: target,
            merges: MergedChatDocument(merges: merges),
            now: now,
            performer: performer
        )
        return performer.calls
    }

    // MARK: Identifier to action

    @Test func clickOpensTheChat() {
        #expect(action(defaultIdentifier) == .open)
    }

    @Test func eachActionIdentifierMapsToItsAction() {
        #expect(action(NotificationAction.replyIdentifier, text: "on my way") == .reply("on my way"))
        #expect(action(NotificationAction.markAsReadIdentifier) == .markAsRead)
        #expect(action(NotificationAction.remindInOneHourIdentifier) == .remindInOneHour)
    }

    @Test func dismissAndUnknownIdentifiersDoNothing() {
        #expect(action("com.apple.UNNotificationDismissActionIdentifier") == nil)
        #expect(action("something.else") == nil)
    }

    /// The text goes as typed: markdown and spaces stay.
    @Test func replyKeepsTheTextAsTyped() {
        #expect(action(NotificationAction.replyIdentifier, text: "  *see* you\n") == .reply("  *see* you\n"))
    }

    @Test func replyWithNoTextDoesNothing() {
        #expect(action(NotificationAction.replyIdentifier, text: nil) == nil)
        #expect(action(NotificationAction.replyIdentifier, text: "") == nil)
        #expect(action(NotificationAction.replyIdentifier, text: " \n\t") == nil)
    }

    // MARK: userInfo

    @Test func targetSurvivesTheUserInfo() {
        let target = NotificationTarget(roomId: "!room", eventId: "$event", threadRoot: "$root")
        #expect(NotificationTarget(userInfo: target.userInfo) == target)
    }

    @Test func targetWithNoThreadHasNoThreadKey() {
        let target = NotificationTarget(roomId: "!room", eventId: "$event")
        #expect(target.userInfo == [NotificationTarget.roomIdKey: "!room", NotificationTarget.eventIdKey: "$event"])
    }

    /// A MATRIX-89 push notification and a reminder carry only the room.
    @Test func userInfoWithOnlyTheRoomIsATarget() {
        let info: [AnyHashable: Any] = ["roomId": "!room", "reminder": true]
        #expect(NotificationTarget(userInfo: info) == NotificationTarget(roomId: "!room"))
    }

    @Test func userInfoWithNoRoomIsNoTarget() {
        #expect(NotificationTarget(userInfo: ["eventId": "$event"]) == nil)
    }

    // MARK: Reply routing

    @Test func replyGoesToTheMainTimelineOfTheRoom() async {
        let calls = await perform(.reply("hi"), on: NotificationTarget(roomId: "!room", eventId: "$event"))
        #expect(calls == [.send(text: "hi", roomId: "!room", threadRoot: nil)])
    }

    /// A message in a thread gets its reply in that thread (MATRIX-216).
    @Test func replyToAMessageInAThreadGoesIntoTheThread() async {
        let target = NotificationTarget(roomId: "!room", eventId: "$reply", threadRoot: "$root")
        let calls = await perform(.reply("hi"), on: target)
        #expect(calls == [.send(text: "hi", roomId: "!room", threadRoot: "$root")])
    }

    /// The reply goes where the message came from, not to the merged
    /// chat's default room.
    @Test func replyInAMergedChatGoesToTheNotifiedRoom() async {
        let calls = await perform(.reply("hi"), on: NotificationTarget(roomId: "!groupme", eventId: "$event"), merges: [seth])
        #expect(calls == [.send(text: "hi", roomId: "!groupme", threadRoot: nil)])
    }

    // MARK: Mark as Read

    @Test func markAsReadRemovesTheNotificationsAndSendsTheReceipt() async {
        let calls = await perform(.markAsRead, on: NotificationTarget(roomId: "!room", eventId: "$event"))
        #expect(calls == [.removeDelivered(["!room"]), .markAsRead(["!room"])])
    }

    /// A merged chat is one chat: each member room is read.
    @Test func markAsReadInAMergedChatReadsEveryMember() async {
        let calls = await perform(.markAsRead, on: NotificationTarget(roomId: "!groupme"), merges: [seth])
        #expect(calls == [.removeDelivered(["!slack", "!groupme"]), .markAsRead(["!slack", "!groupme"])])
    }

    // MARK: Remind in 1 Hour

    @Test func remindSetsAReminderOneHourFromNow() async {
        let calls = await perform(.remindInOneHour, on: NotificationTarget(roomId: "!room"))
        #expect(calls == [.remind(["!room"], now.addingTimeInterval(3600))])
    }

    @Test func remindInAMergedChatRemindsTheMergedChat() async {
        let calls = await perform(.remindInOneHour, on: NotificationTarget(roomId: "!slack"), merges: [seth])
        #expect(calls == [.remind(["!slack", "!groupme"], now.addingTimeInterval(3600))])
    }

    /// The delegate selects the chat; the router calls nothing.
    @Test func openCallsNothing() async {
        let calls = await perform(.open, on: NotificationTarget(roomId: "!room"))
        #expect(calls.isEmpty)
    }

    // MARK: Delivered notifications

    @Test func onlyTheChatsMessageNotificationsAreRemoved() {
        let delivered: [(identifier: String, userInfo: [AnyHashable: Any])] = [
            ("a", ["roomId": "!room", "eventId": "$1"]),
            ("b", ["roomId": "!other", "eventId": "$2"]),
            ("c", ["roomId": "!room", "reminder": true]),
            ("d", ["roomId": "!member", "eventId": "$3"]),
            ("e", [:]),
        ]
        let removed = NotificationTarget.messageNotificationIdentifiers(in: delivered, roomIds: ["!room", "!member"])
        #expect(removed == ["a", "d"])
    }
}

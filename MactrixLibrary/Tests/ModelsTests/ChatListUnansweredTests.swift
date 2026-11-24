import Foundation
@testable import Models
import Testing

/// MATRIX-224: the Unanswered rule and the own-reaction mark.
struct ChatListUnansweredTests {
    private static let time = Date(timeIntervalSince1970: 1_800_000_000.123)
    private static let alice = ChatListSender(userId: "@alice:example.org", displayName: "Alice", isOwn: false)
    private static let me = ChatListSender(userId: "@me:example.org", displayName: "Me", isOwn: true)

    private func event(
        _ content: ChatListPreviewContent,
        from sender: ChatListSender = alice,
        at time: Date = time
    ) -> ChatListLatestEvent {
        ChatListLatestEvent(timestamp: time, sender: sender, content: content)
    }

    // MARK: The rule

    @Test
    func messageFromAnotherPersonIsUnanswered() {
        #expect(ChatListUnanswered.isUnanswered(event(.text("Lunch?")), ownReaction: nil))
    }

    @Test
    func ownMessageIsAnswered() {
        #expect(!ChatListUnanswered.isUnanswered(event(.text("Sure"), from: Self.me), ownReaction: nil))
    }

    @Test
    func noLatestEventIsNotUnanswered() {
        #expect(!ChatListUnanswered.isUnanswered(nil, ownReaction: nil))
    }

    @Test
    func ownReactionOnTheLatestMessageAnswersIt() {
        let latest = event(.text("Lunch?"))
        #expect(!ChatListUnanswered.isUnanswered(latest, ownReaction: latest.messageKey))
    }

    @Test
    func ownReactionOnAnOlderMessageDoesNotAnswerTheNewOne() {
        let older = ChatListMessageKey(senderId: Self.alice.userId, timestamp: Self.time.addingTimeInterval(-60))
        #expect(ChatListUnanswered.isUnanswered(event(.text("Lunch?")), ownReaction: older))
    }

    @Test
    func ownReactionOnAnotherSendersMessageAtTheSameTimeDoesNotCount() {
        let other = ChatListMessageKey(senderId: "@bob:example.org", timestamp: Self.time)
        #expect(ChatListUnanswered.isUnanswered(event(.text("Lunch?")), ownReaction: other))
    }

    @Test(arguments: [
        ChatListPreviewContent.text("Hi"),
        .emote("waves"),
        .image,
        .video,
        .audio,
        .file(name: "plan.pdf"),
        .gallery,
        .sticker,
        .poll(question: "Pizza?"),
        .location,
        .unableToDecrypt,
    ])
    func everyMessageKindCanBeUnanswered(content: ChatListPreviewContent) {
        #expect(content.isMessage)
        #expect(ChatListUnanswered.isUnanswered(event(content), ownReaction: nil))
    }

    @Test(arguments: [
        ChatListPreviewContent.redacted,
        .invite,
        .membership(.joined),
        .membership(.left),
        .other,
    ])
    func otherEventsAreNotUnanswered(content: ChatListPreviewContent) {
        #expect(!content.isMessage)
        #expect(!ChatListUnanswered.isUnanswered(event(content), ownReaction: nil))
    }

    // MARK: The mark a timeline records

    @Test
    func ownReactionOnAnotherPersonsMessageGivesAMark() {
        let message = ChatListMessageKey(senderId: Self.alice.userId, timestamp: Self.time)
        let mark = ChatListUnanswered.ownReactionMark(
            message: message,
            isOwn: false,
            reactionSenderIds: ["@bob:example.org", "@me:example.org"],
            ownUserId: "@me:example.org"
        )
        #expect(mark == message)
    }

    @Test
    func otherPeoplesReactionsGiveNoMark() {
        let message = ChatListMessageKey(senderId: Self.alice.userId, timestamp: Self.time)
        let mark = ChatListUnanswered.ownReactionMark(
            message: message,
            isOwn: false,
            reactionSenderIds: ["@bob:example.org"],
            ownUserId: "@me:example.org"
        )
        #expect(mark == nil)
    }

    @Test
    func ownMessageGivesNoMark() {
        let message = ChatListMessageKey(senderId: Self.me.userId, timestamp: Self.time)
        let mark = ChatListUnanswered.ownReactionMark(
            message: message,
            isOwn: true,
            reactionSenderIds: ["@me:example.org"],
            ownUserId: "@me:example.org"
        )
        #expect(mark == nil)
    }

    @Test
    func markSurvivesACodableRoundTrip() throws {
        // The SDK time is milliseconds; the store keeps the mark as JSON.
        let mark = ChatListMessageKey(
            senderId: Self.alice.userId,
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_800_000_000_123) / 1000)
        )
        let data = try JSONEncoder().encode(["!a": mark])
        let decoded = try JSONDecoder().decode([String: ChatListMessageKey].self, from: data)
        #expect(decoded["!a"] == mark)
    }

    // MARK: The filter on the visible list

    private func entry(_ id: String, minutesAgo: Double, unanswered: Bool) -> ChatListEntry {
        ChatListEntry(
            row: ChatListRowModel(id: id, title: "Title \(id)"),
            lastActivity: Self.time.addingTimeInterval(-minutesAgo * 60),
            isUnanswered: unanswered
        )
    }

    @Test
    func unansweredFilterKeepsTheUnansweredChats() {
        let visible = ChatListMerging.visible(
            entries: [
                entry("!a", minutesAgo: 1, unanswered: true),
                entry("!b", minutesAgo: 2, unanswered: false),
                entry("!c", minutesAgo: 3, unanswered: true),
            ],
            document: MergedChatDocument()
        )
        #expect(visible.filtered(for: .unanswered).ordered.map(\.id) == ["!a", "!c"])
        #expect(visible.filtered(for: .inbox).ordered.map(\.id) == ["!a", "!b", "!c"])
    }

    @Test
    func mergedChatReadsItsNewestMember() {
        let merge = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"])
        let answered = ChatListMerging.visible(
            entries: [
                entry("!s1", minutesAgo: 1, unanswered: false),
                entry("!s2", minutesAgo: 5, unanswered: true),
            ],
            document: MergedChatDocument(merges: [merge])
        )
        #expect(answered.filtered(for: .unanswered).ordered.isEmpty)

        let unanswered = ChatListMerging.visible(
            entries: [
                entry("!s2", minutesAgo: 1, unanswered: true),
                entry("!s1", minutesAgo: 5, unanswered: false),
            ],
            document: MergedChatDocument(merges: [merge])
        )
        #expect(unanswered.filtered(for: .unanswered).ordered.map(\.id) == ["m-seth"])
    }
}

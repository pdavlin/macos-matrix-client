import Foundation
@testable import Models
import Testing

/// MATRIX-168: the targets, the draft, and the confirm rule of a broadcast.
struct BroadcastTests {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)

    /// `!s1` and `!s2` are one merged chat. Its default room is `!s2`.
    private static let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"], defaultRoom: "!s2")

    private static let labels = ChatLabelDocument(labels: [
        ChatLabel(id: "work", name: "Work", rooms: ["!s1", "!w1", "!w2"]),
        ChatLabel(id: "both", name: "Both", rooms: ["!s1", "!s2", "!a"]),
    ])

    private static let spaces = RoomSpaceMap(parents: [
        "!s1": ["!dev"],
        "!s2": ["!dev"],
        "!w1": ["!dev"],
        "!deep": ["!sub"],
        "!sub": ["!dev"],
    ])

    private static let document = MergedChatDocument(merges: [seth])

    private func makeEntry(_ id: String, minutesAgo: Double, isFavourite: Bool = false) -> ChatListEntry {
        ChatListEntry(
            row: ChatListRowModel(id: id, title: "Chat \(id)"),
            lastActivity: Self.base.addingTimeInterval(-minutesAgo * 60),
            isFavourite: isFavourite
        )
    }

    /// Recency order, as the SDK gives it.
    private var entries: [ChatListEntry] {
        [
            makeEntry("!a", minutesAgo: 1),
            makeEntry("!s1", minutesAgo: 2),
            makeEntry("!w1", minutesAgo: 3),
            makeEntry("!s2", minutesAgo: 4),
            makeEntry("!w2", minutesAgo: 5, isFavourite: true),
            makeEntry("!deep", minutesAgo: 6),
        ]
    }

    private func targets(_ filter: ChatListRailFilter) -> [BroadcastTarget] {
        BroadcastTarget.targets(
            entries: entries, filter: filter, labels: Self.labels, spaces: Self.spaces, document: Self.document, now: Self.base
        )
    }

    // MARK: - Targets

    @Test func inboxGivesNoTarget() {
        #expect(targets(.inbox).isEmpty)
    }

    @Test func unknownLabelGivesNoTarget() {
        #expect(targets(.label("gone")).isEmpty)
    }

    /// The pinned grid comes first, then the list in recency order.
    @Test func labelTargetsAreInSidebarOrder() {
        let found = targets(.label("work"))
        #expect(found.map(\.id) == ["!w2", "m-seth", "!w1"])
        #expect(found.map(\.roomId) == ["!w2", "!s1", "!w1"])
    }

    @Test func plainChatTargetsItsOwnRoom() throws {
        let plain = try #require(targets(.label("work")).first { $0.id == "!w1" })
        #expect(plain.roomId == "!w1")
        #expect(plain.mergedChatId == nil)
        #expect(plain.title == "Chat !w1")
    }

    /// The label holds one member only, so the message goes to that member,
    /// not to the default room outside the label.
    @Test func mergedChatIsOneTargetInsideTheFilter() throws {
        let merged = try #require(targets(.label("work")).first { $0.id == "m-seth" })
        #expect(merged.roomId == "!s1")
        #expect(merged.mergedChatId == "m-seth")
        #expect(merged.title == "Seth")
    }

    /// Both members show, so the message goes to the default room.
    @Test func mergedChatUsesItsDefaultRoomWhenTheFilterShowsIt() {
        let found = targets(.label("both"))
        #expect(found.map(\.id) == ["!a", "m-seth"])
        #expect(found.map(\.roomId) == ["!a", "!s2"])
    }

    /// With known activity, the send-target rule picks the room where the
    /// other person wrote last.
    @Test func mergedChatFollowsKnownActivity() {
        let visible = ChatListMerging.visible(
            entries: entries, filter: .label("both"), labels: Self.labels, spaces: Self.spaces, document: Self.document
        )
        let activity = ["!s1": MergedSendTarget.RoomActivity(newestMessageAt: Self.base.addingTimeInterval(-60))]
        let found = BroadcastTarget.targets(items: visible.ordered, filter: .label("both"), activity: activity, now: Self.base)
        #expect(found.map(\.roomId) == ["!a", "!s1"])
    }

    /// A space holds the chats of its sub-spaces. The space is no target.
    @Test func spaceTargets() {
        let found = targets(.space("!dev"))
        #expect(found.map(\.id) == ["m-seth", "!w1", "!deep"])
        #expect(found.map(\.roomId) == ["!s2", "!w1", "!deep"])
        #expect(!found.contains { $0.roomId == "!dev" || $0.roomId == "!sub" })
    }

    @Test func itemsOfTheInboxGiveNoTarget() {
        let visible = ChatListMerging.visible(
            entries: entries, filter: .inbox, labels: Self.labels, spaces: Self.spaces, document: Self.document
        )
        #expect(BroadcastTarget.targets(items: visible.ordered, filter: .inbox).isEmpty)
    }

    // MARK: - Draft

    @Test func newDraftSelectsEveryTarget() {
        let found = targets(.label("work"))
        let draft = BroadcastDraft(targets: found)
        #expect(draft.text.isEmpty)
        #expect(draft.selectedIds == ["!w2", "m-seth", "!w1"])
        #expect(!draft.canReview(targets: found))
    }

    @Test func reviewNeedsTextAndOneTarget() {
        let found = targets(.label("work"))
        var draft = BroadcastDraft(targets: found)
        draft.text = "  \n "
        #expect(!draft.canReview(targets: found))
        draft.text = " Lunch at noon \n"
        #expect(draft.canReview(targets: found))
        #expect(draft.outgoingText == "Lunch at noon")
        draft.selectNone()
        #expect(!draft.canReview(targets: found))
        draft.setSelected(true, id: "!w1")
        #expect(draft.canReview(targets: found))
        #expect(draft.selectedTargets(in: found).map(\.id) == ["!w1"])
        draft.selectAll(found)
        draft.setSelected(false, id: "m-seth")
        #expect(draft.selectedTargets(in: found).map(\.id) == ["!w2", "!w1"])
    }

    /// A checked ID that is not in the list does not count.
    @Test func staleSelectionDoesNotAllowReview() {
        let found = targets(.label("work"))
        let draft = BroadcastDraft(text: "Hello", selectedIds: ["!gone"])
        #expect(!draft.canReview(targets: found))
    }

    // MARK: - Confirm rule

    @Test func twentyTargetsNeedNoTypedCount() {
        #expect(BroadcastConfirmation.typedCountThreshold == 20)
        #expect(!BroadcastConfirmation.needsTypedCount(targetCount: 20))
        #expect(BroadcastConfirmation.isConfirmed(targetCount: 20, typedCount: ""))
        #expect(BroadcastConfirmation.isConfirmed(targetCount: 1, typedCount: ""))
        #expect(!BroadcastConfirmation.isConfirmed(targetCount: 0, typedCount: "0"))
    }

    @Test func twentyOneTargetsNeedTheTypedCount() {
        #expect(BroadcastConfirmation.needsTypedCount(targetCount: 21))
        #expect(!BroadcastConfirmation.isConfirmed(targetCount: 21, typedCount: ""))
        #expect(!BroadcastConfirmation.isConfirmed(targetCount: 21, typedCount: "20"))
        #expect(!BroadcastConfirmation.isConfirmed(targetCount: 21, typedCount: "twenty-one"))
        #expect(BroadcastConfirmation.isConfirmed(targetCount: 21, typedCount: "21"))
        #expect(BroadcastConfirmation.isConfirmed(targetCount: 21, typedCount: " 21 "))
    }

    // MARK: - Emoji tokens

    @Test func emojiTokenTest() {
        #expect(BroadcastText.mayHoldEmojiToken("Done :party_parrot:"))
        #expect(BroadcastText.mayHoldEmojiToken(":a:"))
        #expect(!BroadcastText.mayHoldEmojiToken("Lunch at 12:30"))
        #expect(!BroadcastText.mayHoldEmojiToken("Note: this is: text"))
        #expect(!BroadcastText.mayHoldEmojiToken("::"))
        #expect(!BroadcastText.mayHoldEmojiToken("https://example.org"))
        #expect(!BroadcastText.mayHoldEmojiToken(""))
    }
}

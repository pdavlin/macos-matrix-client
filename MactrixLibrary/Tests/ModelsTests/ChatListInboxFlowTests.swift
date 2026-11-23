import Foundation
@testable import Models
import Testing

/// MATRIX-222: the chat that opens after Archive, Snooze, or Mark as Read on
/// the open chat, and the chats "Archive All Read" archives.
struct ChatListInboxFlowTests {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)

    private static let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"])

    private func entry(_ id: String, minutesAgo: Double, unread: Bool = false, isFavourite: Bool = false) -> ChatListEntry {
        ChatListEntry(
            row: ChatListRowModel(
                id: id,
                title: "Title \(id)",
                isDirect: true,
                unread: ChatListUnread(count: unread ? 1 : 0, isUnread: unread)
            ),
            lastActivity: Self.base.addingTimeInterval(-minutesAgo * 60),
            isFavourite: isFavourite
        )
    }

    /// The sidebar's list for `entries`, with Seth's merged chat folded in.
    private func visible(_ entries: [ChatListEntry]) -> VisibleChatList<ChatListItem> {
        ChatListMerging.visible(entries: entries, document: MergedChatDocument(merges: [Self.seth]))
    }

    /// A, B, C in that order.
    private var plain: [ChatListItem] {
        visible([
            entry("!a", minutesAgo: 1),
            entry("!b", minutesAgo: 2),
            entry("!c", minutesAgo: 3),
        ]).ordered
    }

    // MARK: The next chat

    @Test
    func rowInTheMiddleOpensTheRowBelow() {
        #expect(ChatListInboxFlow.nextChat(after: .room("!b"), in: plain) == .open(.room("!c")))
    }

    @Test
    func firstRowOpensTheRowBelow() {
        #expect(ChatListInboxFlow.nextChat(after: .room("!a"), in: plain) == .open(.room("!b")))
    }

    @Test
    func rowAtTheEndOpensTheRowAbove() {
        #expect(ChatListInboxFlow.nextChat(after: .room("!c"), in: plain) == .open(.room("!b")))
    }

    @Test
    func lastRowLeftSelectsNothing() {
        let items = visible([entry("!a", minutesAgo: 1)]).ordered
        #expect(ChatListInboxFlow.nextChat(after: .room("!a"), in: items) == .clear)
    }

    @Test
    func openChatOutsideTheListKeepsTheSelection() {
        // A chat opened through ⌘K that the filter does not show.
        #expect(ChatListInboxFlow.nextChat(after: .room("!elsewhere"), in: plain) == .keep)
        #expect(ChatListInboxFlow.nextChat(after: .room("!a"), in: []) == .keep)
    }

    @Test
    func mergedChatIsOneRow() {
        // !s1 and !s2 fold into Seth's row, which takes !s1's place.
        let items = visible([
            entry("!a", minutesAgo: 1),
            entry("!s1", minutesAgo: 2),
            entry("!b", minutesAgo: 3),
            entry("!s2", minutesAgo: 4),
        ]).ordered
        #expect(items.map(\.id) == ["!a", "m-seth", "!b"])
        // Archiving the open merged chat opens the row below it, not a member.
        #expect(ChatListInboxFlow.nextChat(after: .merged("m-seth"), in: items) == .open(.room("!b")))
        // The row below the open chat is the merged chat.
        #expect(ChatListInboxFlow.nextChat(after: .room("!a"), in: items) == .open(.merged("m-seth")))
    }

    @Test
    func mergedChatAtTheEndOpensTheRowAbove() {
        let items = visible([
            entry("!a", minutesAgo: 1),
            entry("!s2", minutesAgo: 2),
        ]).ordered
        #expect(ChatListInboxFlow.nextChat(after: .merged("m-seth"), in: items) == .open(.room("!a")))
    }

    @Test
    func walkGoesFromTheGridIntoTheList() {
        let items = visible([
            entry("!a", minutesAgo: 1),
            entry("!fav", minutesAgo: 2, isFavourite: true),
            entry("!b", minutesAgo: 3),
        ]).ordered
        #expect(items.map(\.id) == ["!fav", "!a", "!b"])
        #expect(ChatListInboxFlow.nextChat(after: .room("!fav"), in: items) == .open(.room("!a")))
    }

    // MARK: Archive All Read

    @Test
    func archiveAllReadTakesTheReadRowsOfTheList() {
        let list = visible([
            entry("!a", minutesAgo: 1, unread: true),
            entry("!b", minutesAgo: 2),
            entry("!s1", minutesAgo: 3),
            entry("!fav", minutesAgo: 4, isFavourite: true),
            entry("!c", minutesAgo: 5),
        ])
        let targets = ChatListInboxFlow.archiveAllReadTargets(in: list)
        // The unread row and the pinned favourite stay; the merged chat is one.
        #expect(targets.map(\.id) == ["!b", "m-seth", "!c"])
    }

    @Test
    func unreadMergedChatIsNotArchived() {
        let list = visible([
            entry("!s1", minutesAgo: 1),
            entry("!s2", minutesAgo: 2, unread: true),
            entry("!b", minutesAgo: 3),
        ])
        #expect(ChatListInboxFlow.archiveAllReadTargets(in: list).map(\.id) == ["!b"])
    }

    @Test
    func confirmationGivesTheCount() {
        #expect(ChatListInboxFlow.archiveAllReadTitle(count: 0) == "No Read Chats to Archive")
        #expect(ChatListInboxFlow.archiveAllReadTitle(count: 1) == "Archive 1 Read Chat?")
        #expect(ChatListInboxFlow.archiveAllReadTitle(count: 12) == "Archive 12 Read Chats?")
        #expect(ArchiveAllReadRequest(itemIds: ["!a", "m-seth"]).count == 2)
    }

    @Test
    func noteGivesTheCount() {
        #expect(InboxNotice.archivedAll(count: 1, undoStates: [:]).message == "Archived 1 chat")
        #expect(InboxNotice.archivedAll(count: 3, undoStates: [:]).message == "Archived 3 chats")
    }

    // MARK: Setting and focus

    @Test
    func settingIsOnByDefault() throws {
        let suite = "ChatListInboxFlowTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(InboxFlowPreferences.isOn(in: defaults))
        defaults.set(false, forKey: InboxFlowPreferences.storageKey)
        #expect(!InboxFlowPreferences.isOn(in: defaults))
    }

    @Test
    func nextChatTakesTheComposerFocus() {
        #expect(ChatOpenSource.inboxFlow.asksForComposerFocus)
    }
}

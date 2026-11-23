import Foundation
@testable import Models
import Testing

/// MATRIX-223: Go > Next Unread Chat (⌘U) over the visible list.
struct ChatListNextUnreadTests {
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

    /// The sidebar's walk order for `entries`, with Seth's merged chat
    /// folded in.
    private func ordered(_ entries: [ChatListEntry]) -> [ChatListItem] {
        ChatListMerging.visible(entries: entries, document: MergedChatDocument(merges: [Self.seth])).ordered
    }

    /// A, B (unread), C, D (unread).
    private var items: [ChatListItem] {
        ordered([
            entry("!a", minutesAgo: 1),
            entry("!b", minutesAgo: 2, unread: true),
            entry("!c", minutesAgo: 3),
            entry("!d", minutesAgo: 4, unread: true),
        ])
    }

    @Test
    func opensTheNextUnreadRowBelow() {
        #expect(ChatListNavigation.nextUnread(after: "!a", in: items) == .room("!b"))
        #expect(ChatListNavigation.nextUnread(after: "!c", in: items) == .room("!d"))
    }

    @Test
    func wrapsToTheTop() {
        #expect(ChatListNavigation.nextUnread(after: "!d", in: items) == .room("!b"))
    }

    @Test
    func noUnreadRowGivesNil() {
        let read = ordered([entry("!a", minutesAgo: 1), entry("!b", minutesAgo: 2)])
        #expect(ChatListNavigation.nextUnread(after: "!a", in: read) == nil)
        #expect(ChatListNavigation.nextUnread(after: nil, in: read) == nil)
        #expect(ChatListNavigation.nextUnread(after: nil, in: []) == nil)
    }

    @Test
    func openUnreadChatIsSkipped() {
        // !b is open and unread: the next unread is !d.
        #expect(ChatListNavigation.nextUnread(after: "!b", in: items) == .room("!d"))
        // The open chat is the only unread row: nothing to open.
        let one = ordered([entry("!a", minutesAgo: 1, unread: true), entry("!b", minutesAgo: 2)])
        #expect(ChatListNavigation.nextUnread(after: "!a", in: one) == nil)
    }

    @Test
    func noOpenChatStartsAtTheTop() {
        #expect(ChatListNavigation.nextUnread(after: nil, in: items) == .room("!b"))
        // An open chat the list does not show counts as none.
        #expect(ChatListNavigation.nextUnread(after: "!elsewhere", in: items) == .room("!b"))
    }

    @Test
    func mergedChatIsOneRow() {
        // !s2 is unread, so Seth's merged row is unread. It sits where !s1
        // is in the SDK order.
        let merged = ordered([
            entry("!a", minutesAgo: 1),
            entry("!s1", minutesAgo: 2),
            entry("!b", minutesAgo: 3),
            entry("!s2", minutesAgo: 4, unread: true),
        ])
        #expect(merged.map(\.id) == ["!a", "m-seth", "!b"])
        #expect(ChatListNavigation.nextUnread(after: "!a", in: merged) == .merged("m-seth"))
        // From the merged chat itself, nothing else is unread.
        #expect(ChatListNavigation.nextUnread(after: "m-seth", in: merged) == nil)
        // From the last row, the walk wraps to the merged chat.
        #expect(ChatListNavigation.nextUnread(after: "!b", in: merged) == .merged("m-seth"))
    }

    @Test
    func pinnedGridComesFirst() {
        let pinned = ordered([
            entry("!a", minutesAgo: 1),
            entry("!fav", minutesAgo: 2, unread: true, isFavourite: true),
            entry("!b", minutesAgo: 3, unread: true),
        ])
        #expect(pinned.map(\.id) == ["!fav", "!a", "!b"])
        #expect(ChatListNavigation.nextUnread(after: nil, in: pinned) == .room("!fav"))
        #expect(ChatListNavigation.nextUnread(after: "!b", in: pinned) == .room("!fav"))
    }
}

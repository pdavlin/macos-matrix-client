import Foundation
@testable import Models
import Testing

/// MATRIX-248: the iOS chat list follows the Mac's inbox state and merged
/// chats through the Mac sidebar's rules. iOS calls
/// `ChatListMerging.visible(entries:filter:labels:spaces:document:inbox:placement:)`
/// (through Core's `MatrixClient.visibleChatList`) with no rail and no
/// labels, and narrows the SDK list with
/// `ChatListFilter.narrowingRoomIds(rail:placementRoomIds:draftRoomIds:)`
/// with no rail.
struct ChatListIOSInboxTests {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)
    private static let merges = MergedChatDocument(merges: [
        MergedChat(id: "m-seth", name: "Seth", rooms: ["!seth-signal", "!seth-wa"]),
    ])

    private func time(_ minutes: Double) -> Date {
        Self.base.addingTimeInterval(minutes * 60)
    }

    /// The SDK order is recency: `!a` is the newest room.
    private var entries: [ChatListEntry] {
        [
            entry("!a", minutesAgo: 1),
            entry("!seth-wa", minutesAgo: 2),
            entry("!b", minutesAgo: 3),
            entry("!seth-signal", minutesAgo: 4),
            entry("!c", minutesAgo: 5),
        ]
    }

    private func entry(_ id: String, minutesAgo: Double?) -> ChatListEntry {
        ChatListEntry(
            row: ChatListRowModel(id: id, title: id),
            lastActivity: minutesAgo.map { time(-$0) }
        )
    }

    /// The iOS list for a list filter: no rail, no labels.
    private func iosList(
        _ filter: ChatListFilter,
        entries: [ChatListEntry]? = nil,
        inbox: InboxStateDocument = InboxStateDocument(),
        labels: ChatLabelDocument = ChatLabelDocument()
    ) -> [ChatListItem] {
        ChatListMerging.visible(
            entries: entries ?? self.entries,
            filter: .inbox,
            labels: labels,
            spaces: RoomSpaceMap(),
            document: Self.merges,
            inbox: inbox,
            placement: filter.inboxPlacement
        ).ordered
    }

    private func narrowing(_ filter: ChatListFilter, inbox: InboxStateDocument) -> [String]? {
        filter.narrowingRoomIds(
            rail: nil,
            placementRoomIds: { inbox.roomIds(in: $0, merges: Self.merges) },
            draftRoomIds: { [] }
        )
    }

    // MARK: Placement

    @Test
    func archivedAndSnoozedChatsLeaveTheInboxAndLowPriority() {
        var inbox = InboxStateDocument()
        inbox.archive(["!a"], at: time(0))
        inbox.snooze(["!b"], until: time(60), at: time(0))

        for filter in [ChatListFilter.inbox, .lowPriority] {
            #expect(iosList(filter, inbox: inbox).map(\.id) == ["m-seth", "!c"])
        }
    }

    @Test
    func archivedAndSnoozedFiltersShowOnlyTheirChats() {
        var inbox = InboxStateDocument()
        inbox.archive(["!a", "!seth-signal", "!seth-wa"], at: time(0))
        inbox.snooze(["!b"], until: time(60), at: time(0))

        #expect(iosList(.archived, inbox: inbox).map(\.id) == ["!a", "m-seth"])
        #expect(iosList(.snoozed, inbox: inbox).map(\.id) == ["!b"])
    }

    @Test
    func aMergedChatIsArchivedAsOneChat() {
        // One member archived and the other in the Inbox: the merged chat
        // stays in the Inbox, with both members.
        var inbox = InboxStateDocument()
        inbox.archive(["!seth-wa"], at: time(0))

        let shown = iosList(.inbox, inbox: inbox)

        #expect(shown.map(\.id) == ["!a", "m-seth", "!b", "!c"])
        #expect(shown[1].roomIds == ["!seth-signal", "!seth-wa"])
        #expect(iosList(.archived, inbox: inbox).isEmpty)
    }

    @Test
    func theInboxKeepsTheChatsOfLabelsHiddenFromIt() {
        // iOS passes no labels: it has no label rail to reach these chats.
        let labels = ChatLabelDocument(labels: [ChatLabel(id: "work", name: "Work", inboxVisibility: .hidden, rooms: ["!b"])])

        #expect(iosList(.inbox).map(\.id).contains("!b"))
        #expect(!iosList(.inbox, labels: labels).map(\.id).contains("!b"))
    }

    // MARK: Merging

    @Test
    func aMergedChatIsOneRowAtItsNewestMembersPlace() {
        let shown = iosList(.inbox)

        #expect(shown.map(\.id) == ["!a", "m-seth", "!b", "!c"])
        #expect(shown[1].row.title == "Seth")
        #expect(shown[1].mergedChat?.memberRoomIds == ["!seth-signal", "!seth-wa"])
    }

    @Test
    func theNewestMemberIsTheOneWithTheNewestMessage() {
        #expect(iosList(.inbox)[1].mergedChat?.newestRoomId == "!seth-wa")

        let signalNewer = [entry("!seth-signal", minutesAgo: 1), entry("!seth-wa", minutesAgo: 9)]
        #expect(iosList(.inbox, entries: signalNewer).first?.mergedChat?.newestRoomId == "!seth-signal")
    }

    @Test
    func theNewestMemberTieGoesToTheSDKOrderAndNoTimeIsOldest() {
        let tie = [entry("!seth-signal", minutesAgo: 3), entry("!seth-wa", minutesAgo: 3)]
        #expect(iosList(.inbox, entries: tie).first?.mergedChat?.newestRoomId == "!seth-signal")

        let noTime = [entry("!seth-wa", minutesAgo: nil), entry("!seth-signal", minutesAgo: 30)]
        #expect(iosList(.inbox, entries: noTime).first?.mergedChat?.newestRoomId == "!seth-signal")
    }

    @Test
    func aMergedChatWithOneMemberInTheListOpensThatMember() {
        // The filter holds one member only (the other is low priority).
        let shown = iosList(.inbox, entries: [entry("!seth-signal", minutesAgo: 4)])

        #expect(shown.first?.mergedChat?.newestRoomId == "!seth-signal")
        #expect(shown.first?.roomIds == ["!seth-signal"])
    }

    // MARK: Narrowing

    @Test
    func archivedAndSnoozedNarrowTheSDKListToTheirChats() {
        var inbox = InboxStateDocument()
        inbox.archive(["!a", "!seth-wa", "!seth-signal"], at: time(0))
        inbox.snooze(["!b"], until: time(60), at: time(0))

        #expect(narrowing(.archived, inbox: inbox) == ["!a", "!seth-signal", "!seth-wa"])
        #expect(narrowing(.snoozed, inbox: inbox) == ["!b"])
        #expect(narrowing(.inbox, inbox: inbox) == nil)
        #expect(narrowing(.lowPriority, inbox: inbox) == nil)
    }

    @Test
    func noArchivedChatNarrowsTheSDKListToNoRoom() {
        #expect(narrowing(.archived, inbox: InboxStateDocument()) == [])
        #expect(narrowing(.snoozed, inbox: InboxStateDocument()) == [])
    }
}

/// MATRIX-248: the merged chat's search mark and the avatar and title rules
/// that the chat list and the iOS search share.
struct ChatListSharedMergedRulesTests {
    private static let merges = MergedChatDocument(merges: [MergedChat(id: "m", name: "Seth", rooms: ["!a", "!b"])])
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func searchMarkNamesThePlacement() {
        let until = Self.now.addingTimeInterval(3600)
        var inbox = InboxStateDocument()
        inbox.archive(["!x"], at: Self.now)
        inbox.snooze(["!a", "!b"], until: until, at: Self.now)

        #expect(inbox.searchMark(of: "!x", merges: Self.merges, now: Self.now) == "Archived")
        #expect(inbox.searchMark(of: "!a", merges: Self.merges, now: Self.now) == InboxTimeText.snoozed(until: until, now: Self.now))
        #expect(inbox.searchMark(of: "!b", merges: Self.merges, now: Self.now) == InboxTimeText.snoozed(until: until, now: Self.now))
        #expect(inbox.searchMark(of: "!y", merges: Self.merges, now: Self.now) == nil)
    }

    @Test
    func searchMarkTreatsAMergedChatAsOneChat() {
        var inbox = InboxStateDocument()
        inbox.archive(["!a"], at: Self.now)

        // "!b" is in the Inbox, so the merged chat is.
        #expect(inbox.searchMark(of: "!a", merges: Self.merges, now: Self.now) == nil)
    }

    @Test
    func titleIsTheNameElseTheAvatarMembersTitle() {
        #expect(ChatListMerging.title(of: MergedChat(id: "m", name: " Seth ", rooms: []), avatarMemberTitle: "A") == "Seth")
        #expect(ChatListMerging.title(of: MergedChat(id: "m", name: "", rooms: []), avatarMemberTitle: "A") == "A")
    }

    @Test
    func avatarMemberIsTheChosenRoomElseTheFirstWithAnImage() {
        let members = [("!a", false), ("!b", true), ("!c", true)]
        func pick(_ merge: MergedChat) -> String? {
            ChatListMerging.avatarMember(merge: merge, ordered: members, roomId: { $0.0 }, hasAvatarImage: { $0.1 })?.0
        }

        #expect(pick(MergedChat(id: "m", name: "", rooms: ["!a", "!b", "!c"])) == "!b")
        #expect(pick(MergedChat(id: "m", name: "", rooms: ["!a", "!b", "!c"], avatarRoom: "!c")) == "!c")
        #expect(pick(MergedChat(id: "m", name: "", rooms: ["!a", "!b", "!c"], avatarRoom: "!gone")) == "!b")
    }
}

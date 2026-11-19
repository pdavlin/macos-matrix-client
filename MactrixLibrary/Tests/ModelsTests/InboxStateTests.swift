import Foundation
@testable import Models
import Testing

/// MATRIX-206: the inbox-state model, its codec, the archive rules, and how
/// the chat list and the Dock badge read it.
struct InboxStateTests {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)
    private static let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"])
    private static let merges = MergedChatDocument(merges: [seth])

    private func time(_ minutes: Double) -> Date {
        Self.base.addingTimeInterval(minutes * 60)
    }

    // MARK: Codec

    @Test
    func roundTripKeepsEveryFieldAndEqualsTheWrittenDocument() throws {
        var document = InboxStateDocument()
        document.archive(["!a"], at: time(0).addingTimeInterval(0.000_4))
        document.update(["!b"]) {
            $0.snoozedUntil = time(60)
            $0.snoozedAt = time(1)
            $0.remindAt = time(30)
            $0.remindSetAt = time(1)
        }
        let json = try document.jsonString()
        let read = InboxStateDocument.read(json)
        #expect(read == .parsed(document))
        #expect(json.contains("\"archived_at\":1800000000000"))
    }

    @Test
    func unknownFieldsSurviveAWrite() throws {
        let json = #"{"version":1,"future":true,"rooms":{"!a":{"archived_at":1800000000000,"pin":"x"}}}"#
        guard case var .parsed(document) = InboxStateDocument.read(json) else {
            Issue.record("did not parse")
            return
        }
        document.archive(["!b"], at: time(5))
        let written = try document.jsonString()
        #expect(written.contains("\"future\":true"))
        #expect(written.contains("\"pin\":\"x\""))
    }

    @Test
    func unknownFieldsOfARoomGoWithItsState() throws {
        let json = #"{"version":1,"rooms":{"!a":{"archived_at":1800000000000,"pin":"x"}}}"#
        guard case var .parsed(document) = InboxStateDocument.read(json) else {
            Issue.record("did not parse")
            return
        }
        document.unarchive(["!a"])
        #expect(document.rooms.isEmpty)
        #expect(try !document.jsonString().contains("pin"))
    }

    @Test
    func missingVersionAndRoomsReadAsEmptyVersionOne() {
        #expect(InboxStateDocument.read("{}") == .parsed(InboxStateDocument()))
        #expect(InboxStateDocument.read(nil) == .empty)
    }

    @Test
    func newerVersionIsShownButNotWritable() {
        let read = InboxStateDocument.read(#"{"version":2,"rooms":{"!a":{"archived_at":1800000000000}}}"#)
        #expect(read.document.placement(of: "!a") == .archived)
        #expect(read.writableBase == nil)
    }

    @Test
    func unreadableEventShowsNothingAndRefusesWrites() {
        let read = InboxStateDocument.read(#"{"rooms":[1,2]}"#)
        #expect(read.document == InboxStateDocument())
        #expect(read.writableBase == nil)
    }

    @Test
    func echoGateAcceptsTheRoundTrippedWrite() throws {
        var gate = InboxStateEchoGate()
        var document = InboxStateDocument()
        document.archive(["!a"], at: Date(timeIntervalSince1970: 1_800_000_000.123_456))
        gate.didWrite(document, now: time(0))
        #expect(gate.accept(.empty, now: time(0)) == nil)
        let echo = try InboxStateDocument.read(document.jsonString())
        #expect(gate.accept(echo, now: time(0)) == echo)
        #expect(gate.pendingDocument(now: time(0)) == nil)
    }

    // MARK: Archive and unarchive

    @Test
    func archiveEndsASnoozeAndKeepsAReminder() {
        var document = InboxStateDocument(rooms: [
            "!a": InboxRoomState(snoozedUntil: time(60), snoozedAt: time(0), remindAt: time(30), remindSetAt: time(0)),
        ])
        document.archive(["!a"], at: time(1))
        let state = document.state(of: "!a")
        #expect(state.archivedAt == time(1))
        #expect(state.snoozedUntil == nil)
        #expect(state.snoozedAt == nil)
        #expect(state.remindAt == time(30))
        #expect(document.placement(of: "!a") == .archived)
    }

    @Test
    func unarchiveRemovesAnEmptyEntry() {
        var document = InboxStateDocument()
        document.archive(["!a"], at: time(0))
        document.unarchive(["!a"])
        #expect(document.rooms.isEmpty)
        #expect(document.placement(of: "!a") == .inbox)
    }

    @Test
    func actionOnAMemberWritesTheWholeMergedChat() {
        #expect(InboxStateDocument.chatRoomIds(for: ["!s2", "!x", "!s1"], merges: Self.merges) == ["!s1", "!s2", "!x"])
    }

    @Test
    func mergedChatIsInTheInboxWhenAnyMemberIs() {
        let document = InboxStateDocument(rooms: ["!s1": InboxRoomState(archivedAt: time(0))])
        #expect(document.placement(of: "!s1", merges: Self.merges) == .inbox)
        #expect(document.roomIds(in: .archived, merges: Self.merges).isEmpty)

        var all = document
        all.archive(["!s1", "!s2"], at: time(0))
        #expect(all.placement(of: "!s2", merges: Self.merges) == .archived)
        #expect(all.hiddenRoomIds(merges: Self.merges) == ["!s1", "!s2"])
    }

    @Test
    func archivedFilterShowsArchivedChatsAndOtherFiltersDoNot() {
        #expect(ChatListFilter.archived.inboxPlacement == .archived)
        for filter in ChatListFilter.allCases where filter != .archived && filter != .snoozed {
            #expect(filter.inboxPlacement == .inbox)
        }
    }

    // MARK: Action time

    @Test
    func actionTimeIsNowUnlessTheLatestEventIsLater() {
        #expect(InboxStateDocument.actionTime(now: time(0), latestActivity: nil) == time(0))
        #expect(InboxStateDocument.actionTime(now: time(0), latestActivity: time(-5)) == time(0))
        #expect(InboxStateDocument.actionTime(now: time(0), latestActivity: time(1)) > time(1))
    }

    // MARK: Activity rule

    @Test
    func messageFromAnotherPersonUnarchives() {
        var document = InboxStateDocument()
        document.archive(["!a"], at: time(0))
        let changed = document.applyActivity(InboxActivity(timestamp: time(1), isOwn: false), in: "!a", merges: Self.merges)
        #expect(changed)
        #expect(document.placement(of: "!a") == .inbox)
    }

    @Test
    func ownMessageDoesNotUnarchive() {
        var document = InboxStateDocument()
        document.archive(["!a"], at: time(0))
        let changed = document.applyActivity(InboxActivity(timestamp: time(1), isOwn: true), in: "!a", merges: Self.merges)
        #expect(!changed)
        #expect(document.placement(of: "!a") == .archived)
    }

    @Test
    func olderMessageDoesNotUnarchive() {
        var document = InboxStateDocument()
        document.archive(["!a"], at: time(0))
        let same = document.applyActivity(InboxActivity(timestamp: time(0), isOwn: false), in: "!a", merges: Self.merges)
        let older = document.applyActivity(InboxActivity(timestamp: time(-1), isOwn: false), in: "!a", merges: Self.merges)
        #expect(!same)
        #expect(!older)
    }

    @Test
    func messageInOneMemberUnarchivesTheMergedChat() {
        var document = InboxStateDocument()
        document.archive(["!s1", "!s2"], at: time(0))
        document.applyActivity(InboxActivity(timestamp: time(2), isOwn: false), in: "!s2", merges: Self.merges)
        #expect(document.rooms.isEmpty)
    }

    @Test
    func messageFromAnotherPersonEndsASnoozeAndDropsAReminder() {
        var document = InboxStateDocument(rooms: [
            "!a": InboxRoomState(snoozedUntil: time(60), snoozedAt: time(0)),
            "!b": InboxRoomState(remindAt: time(60), remindSetAt: time(0)),
        ])
        document.applyActivity(InboxActivity(timestamp: time(1), isOwn: false), in: "!a", merges: Self.merges)
        document.applyActivity(InboxActivity(timestamp: time(1), isOwn: false), in: "!b", merges: Self.merges)
        #expect(document.rooms.isEmpty)
    }

    // MARK: Chat list and badge

    private func entry(_ id: String, minutesAgo: Double) -> ChatListEntry {
        ChatListEntry(
            row: ChatListRowModel(id: id, title: id, unread: ChatListUnread(count: 1, isUnread: true)),
            lastActivity: time(-minutesAgo)
        )
    }

    private func shownIds(_ filter: ChatListRailFilter, inbox: InboxStateDocument, placement: InboxPlacement) -> [String] {
        let labels = ChatLabelDocument(labels: [ChatLabel(id: "work", name: "Work", rooms: ["!a", "!b", "!s1"])])
        let spaces = RoomSpaceMap(parents: ["!a": ["!dev"], "!b": ["!dev"]])
        return ChatListMerging.visible(
            entries: [entry("!a", minutesAgo: 1), entry("!b", minutesAgo: 2), entry("!s1", minutesAgo: 3), entry("!s2", minutesAgo: 4)],
            filter: filter,
            labels: labels,
            spaces: spaces,
            document: Self.merges,
            inbox: inbox,
            placement: placement
        ).ordered.map(\.id)
    }

    @Test
    func archivedChatLeavesTheInboxAndEveryRailFilter() {
        var inbox = InboxStateDocument()
        inbox.archive(["!a", "!s1", "!s2"], at: time(0))
        #expect(shownIds(.inbox, inbox: inbox, placement: .inbox) == ["!b"])
        #expect(shownIds(.label("work"), inbox: inbox, placement: .inbox) == ["!b"])
        #expect(shownIds(.space("!dev"), inbox: inbox, placement: .inbox) == ["!b"])
    }

    @Test
    func archivedFilterShowsOnlyArchivedChatsWithTheMergedChatAsOne() {
        var inbox = InboxStateDocument()
        inbox.archive(["!a", "!s1", "!s2"], at: time(0))
        #expect(shownIds(.inbox, inbox: inbox, placement: .archived) == ["!a", "m-seth"])
        #expect(shownIds(.space("!dev"), inbox: inbox, placement: .archived) == ["!a"])
    }

    @Test
    func archivedChatsDoNotCountInTheDockBadge() {
        let chats = ["!a", "!b", "!s1", "!s2"].map { UnreadChatState(roomId: $0, numUnreadNotifications: 1) }
        #expect(DockBadge.unreadChatCount(chats, labelMutedRoomIds: [], mergedChats: Self.merges) == 3)
        var inbox = InboxStateDocument()
        inbox.archive(["!a", "!s1", "!s2"], at: time(0))
        let count = DockBadge.unreadChatCount(
            chats,
            labelMutedRoomIds: [],
            mergedChats: Self.merges,
            hiddenRoomIds: inbox.hiddenRoomIds(merges: Self.merges)
        )
        #expect(count == 1)
    }
}

@testable import MactrixiOS
import MatrixRustSDK
import Models
import XCTest

/// MATRIX-84: the iOS room list groups and orders rooms like the Mac sidebar.
@MainActor
final class RoomListTests: XCTestCase {
    private typealias Item = SampleRoomListItem

    func testSectionsFollowMacGroupingAndDropSpaces() {
        let sections = RoomListSections.make(from: Item.all)

        XCTAssertEqual(sections.map(\.kind), [.favorites, .directs, .rooms])
        XCTAssertEqual(sections[0].chats.map(\.id), ["!fav"])
        XCTAssertEqual(sections[1].chats.map(\.id), ["!dm1", "!dm2"])
        XCTAssertEqual(sections[2].chats.map(\.id), ["!room1", "!room2"])
        XCTAssertFalse(sections.flatMap(\.chats).contains { $0.isSpace })
    }

    func testSectionsKeepTheSDKRecencyOrder() {
        let items = [
            Item(id: "!c", title: "Newest"),
            Item(id: "!a", title: "Older", isDirect: true),
            Item(id: "!b", title: "Oldest"),
        ]

        let sections = RoomListSections.make(from: items)

        XCTAssertEqual(sections.map(\.kind), [.directs, .rooms])
        XCTAssertEqual(sections[1].chats.map(\.id), ["!c", "!b"])
    }

    func testFavoriteDirectMessageAppearsOnlyInFavorites() {
        let items = [Item(id: "!dm", title: "Alex", isFavourite: true, isDirect: true)]

        let sections = RoomListSections.make(from: items)

        XCTAssertEqual(sections.map(\.kind), [.favorites])
    }

    /// MATRIX-247: the next page loads when the list's last row shows.
    func testLastRowIsTheLastRoomOfTheLastSection() {
        let sections = RoomListSections.make(from: Item.all)

        XCTAssertEqual(RoomListSections.lastRoomID(in: sections), "!room2")
    }

    func testLastRowFollowsTheSectionsNotTheSDKOrder() {
        let items = [
            Item(id: "!room", title: "Room"),
            Item(id: "!dm", title: "Alex", isDirect: true),
        ]

        let sections = RoomListSections.make(from: items)

        XCTAssertEqual(RoomListSections.lastRoomID(in: sections), "!room")
    }

    func testEmptyListHasNoLastRow() {
        XCTAssertNil(RoomListSections.lastRoomID(in: RoomListSections.make(from: [Item]())))
    }

    func testEmptyListHasNoSections() {
        XCTAssertTrue(RoomListSections.make(from: [Item]()).isEmpty)
        XCTAssertTrue(RoomListSections.make(from: [Item(id: "!s", title: "Space", isSpace: true)]).isEmpty)
    }

    // MARK: Merged chats and the inbox state (MATRIX-248)

    private var sethAndOthers: [Item] {
        Item.sethMembers + Item.all
    }

    func testMergedChatIsOneRowWithTheMergedName() throws {
        let chats = Item.chats(sethAndOthers)
        let directs = try XCTUnwrap(RoomListSections.make(chats: chats).first { $0.kind == .directs })

        XCTAssertEqual(directs.chats.map(\.id), ["merged-seth", "!dm1", "!dm2"])
        guard case let .merged(merged) = directs.chats.first else {
            return XCTFail("the first direct chat is not the merged chat")
        }
        XCTAssertEqual(merged.row.title, "Seth")
        XCTAssertFalse(chats.contains { $0.id == "!seth-wa" || $0.id == "!seth-signal" })
    }

    func testMergedRowOpensItsNewestMemberRoom() throws {
        let merged = try XCTUnwrap(Item.chats(sethAndOthers).first { $0.id == "merged-seth" })

        XCTAssertEqual(merged.roomToOpen, "!seth-wa")
    }

    func testMergedRowOpensTheOtherMemberWhenItIsNewer() throws {
        let rooms = Array(Item.sethMembers.reversed()) + Item.all
        let merged = try XCTUnwrap(Item.chats(rooms).first { $0.id == "merged-seth" })

        XCTAssertEqual(merged.roomToOpen, "!seth-signal")
    }

    func testMergedRowAddsUpItsMembersUnreadCounts() throws {
        guard case let .merged(merged) = try XCTUnwrap(Item.chats(sethAndOthers).first { $0.id == "merged-seth" }) else {
            return XCTFail("no merged chat")
        }

        XCTAssertEqual(merged.row.unread.count, 3)
        XCTAssertTrue(merged.row.unread.isUnread)
    }

    func testPlainRowOpensItsOwnRoom() {
        XCTAssertEqual(Item.chats(Item.all).map(\.roomToOpen), Item.chats(Item.all).map(\.id))
    }

    func testArchivedAndSnoozedChatsLeaveTheInbox() {
        var inbox = InboxStateDocument()
        inbox.archive(["!dm1"], at: .now)
        inbox.snooze(["!seth-wa", "!seth-signal"], until: .now.addingTimeInterval(3600), at: .now)

        let ids = Item.chats(sethAndOthers, inbox: inbox).map(\.id)

        XCTAssertFalse(ids.contains("!dm1"))
        XCTAssertFalse(ids.contains("merged-seth"))
        XCTAssertEqual(Item.chats(sethAndOthers, inbox: inbox, filter: .archived).map(\.id), ["!dm1"])
        XCTAssertEqual(Item.chats(sethAndOthers, inbox: inbox, filter: .snoozed).map(\.id), ["merged-seth"])
    }

    func testRowsLeaveOutRoomsTheListDoesNotHold() {
        let items = ChatListMerging.items(entries: [Item.all[1].chatListEntry()], document: MergedChatDocument())

        XCTAssertTrue(RoomListChats.make(from: items, rooms: [Item]()).isEmpty)
    }

    func testLastRowCanBeAMergedChat() {
        let sections = RoomListSections.make(chats: Item.chats(Item.sethMembers))

        XCTAssertEqual(RoomListSections.lastRoomID(in: sections), "merged-seth")
    }

    func testOnlyExplicitMuteShowsMuted() {
        XCTAssertTrue(RoomMuteState.isMuted(.mute))
        XCTAssertFalse(RoomMuteState.isMuted(.mentionsAndKeywordsOnly))
        XCTAssertFalse(RoomMuteState.isMuted(.allMessages))
        XCTAssertFalse(RoomMuteState.isMuted(nil))
    }

    func testEmptyStateIsLoadingUntilTheRoomListRuns() {
        XCTAssertTrue(RoomListLoading.isLoading(nil))
        XCTAssertTrue(RoomListLoading.isLoading(.initial))
        XCTAssertTrue(RoomListLoading.isLoading(.settingUp))
        XCTAssertTrue(RoomListLoading.isLoading(.recovering))
        XCTAssertFalse(RoomListLoading.isLoading(.running))
        XCTAssertFalse(RoomListLoading.isLoading(.error))
        XCTAssertFalse(RoomListLoading.isLoading(.terminated))
    }

    func testPhoneUsesStackAndIPadUsesSplit() {
        XCTAssertTrue(RoomNavigationLayout.usesStack(for: .phone))
        XCTAssertFalse(RoomNavigationLayout.usesStack(for: .pad))
    }
}

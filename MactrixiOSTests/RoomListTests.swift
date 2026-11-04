@testable import MactrixiOS
import MatrixRustSDK
import XCTest

/// MATRIX-84: the iOS room list groups and orders rooms like the Mac sidebar.
@MainActor
final class RoomListTests: XCTestCase {
    private typealias Item = SampleRoomListItem

    func testSectionsFollowMacGroupingAndDropSpaces() {
        let sections = RoomListSections.make(from: Item.all)

        XCTAssertEqual(sections.map(\.kind), [.favorites, .directs, .rooms])
        XCTAssertEqual(sections[0].rooms.map(\.id), ["!fav"])
        XCTAssertEqual(sections[1].rooms.map(\.id), ["!dm1", "!dm2"])
        XCTAssertEqual(sections[2].rooms.map(\.id), ["!room1", "!room2"])
        XCTAssertFalse(sections.flatMap(\.rooms).contains { $0.isSpace })
    }

    func testSectionsKeepTheSDKRecencyOrder() {
        let items = [
            Item(id: "!c", title: "Newest"),
            Item(id: "!a", title: "Older", isDirect: true),
            Item(id: "!b", title: "Oldest"),
        ]

        let sections = RoomListSections.make(from: items)

        XCTAssertEqual(sections.map(\.kind), [.directs, .rooms])
        XCTAssertEqual(sections[1].rooms.map(\.id), ["!c", "!b"])
    }

    func testFavoriteDirectMessageAppearsOnlyInFavorites() {
        let items = [Item(id: "!dm", title: "Alex", isFavourite: true, isDirect: true)]

        let sections = RoomListSections.make(from: items)

        XCTAssertEqual(sections.map(\.kind), [.favorites])
    }

    func testEmptyListHasNoSections() {
        XCTAssertTrue(RoomListSections.make(from: [Item]()).isEmpty)
        XCTAssertTrue(RoomListSections.make(from: [Item(id: "!s", title: "Space", isSpace: true)]).isEmpty)
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

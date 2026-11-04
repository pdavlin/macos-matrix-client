import Foundation
@testable import Models
import Testing

/// MATRIX-115: the sidebar's visible rooms and the Go menu's walk over
/// them (D-7b, D-7c).
struct VisibleChatListTests {
    private struct TestRoom: Identifiable, Equatable {
        let id: String
        var isFavourite = false
    }

    private static let labels = ChatLabelDocument(labels: [
        ChatLabel(id: "work", name: "Work", rooms: ["!w1", "!w2"]),
        ChatLabel(id: "fam", name: "Family", inboxVisibility: .hidden, rooms: ["!f1", "!fav-f"]),
    ])

    private static let rooms = [
        TestRoom(id: "!a"),
        TestRoom(id: "!fav1", isFavourite: true),
        TestRoom(id: "!f1"),
        TestRoom(id: "!w1"),
        TestRoom(id: "!fav-f", isFavourite: true),
        TestRoom(id: "!b"),
        TestRoom(id: "!fav2", isFavourite: true),
    ]

    private func visible(
        _ rooms: [TestRoom] = rooms,
        labels: ChatLabelDocument = labels,
        selectedLabelId: String? = nil
    ) -> VisibleChatList<TestRoom> {
        .visible(rooms: rooms, labels: labels, selectedLabelId: selectedLabelId, isFavourite: \.isFavourite)
    }

    // MARK: Visible rooms

    @Test
    func inboxDropsHiddenLabelRoomsAndSplitsFavourites() {
        let list = visible()
        #expect(list.favorites.map(\.id) == ["!fav1", "!fav2"])
        #expect(list.list.map(\.id) == ["!a", "!w1", "!b"])
    }

    @Test
    func orderedIsTheGridThenTheList() {
        #expect(visible().ordered.map(\.id) == ["!fav1", "!fav2", "!a", "!w1", "!b"])
    }

    @Test
    func selectedLabelShowsItsHiddenRooms() {
        // The SDK narrows `rooms` to the label's set; this keeps all of them.
        let labelRooms = Self.rooms.filter { ["!f1", "!fav-f"].contains($0.id) }
        let list = visible(labelRooms, selectedLabelId: "fam")
        #expect(list.favorites.map(\.id) == ["!fav-f"])
        #expect(list.list.map(\.id) == ["!f1"])
    }

    @Test
    func unknownSelectedLabelIsTheInbox() {
        #expect(visible(selectedLabelId: "gone").ordered == visible().ordered)
    }

    @Test
    func keepsTheSDKOrder() {
        let rooms = [TestRoom(id: "!z"), TestRoom(id: "!y", isFavourite: true), TestRoom(id: "!x"), TestRoom(id: "!w", isFavourite: true)]
        let list = visible(rooms, labels: ChatLabelDocument())
        #expect(list.ordered.map(\.id) == ["!y", "!w", "!z", "!x"])
    }

    // MARK: ⌘1…⌘9

    private func rooms(favourites: Int, others: Int) -> [TestRoom] {
        (0 ..< favourites).map { TestRoom(id: "!fav\($0)", isFavourite: true) }
            + (0 ..< others).map { TestRoom(id: "!room\($0)") }
    }

    @Test
    func threeFavouritesThenTheList() {
        // D-7b: ⌘1–⌘3 favourites, ⌘4 the first list row, ⌘5 the second.
        let ordered = visible(rooms(favourites: 3, others: 10), labels: ChatLabelDocument()).ordered
        let targets = ChatListNavigation.shortcutTargets(in: ordered).map(\.id)
        #expect(targets == ["!fav0", "!fav1", "!fav2", "!room0", "!room1", "!room2", "!room3", "!room4", "!room5"])
    }

    @Test
    func nineOrMoreFavouritesTakeEveryKey() {
        let ordered = visible(rooms(favourites: 11, others: 4), labels: ChatLabelDocument()).ordered
        let targets = ChatListNavigation.shortcutTargets(in: ordered).map(\.id)
        #expect(targets == (0 ..< 9).map { "!fav\($0)" })
    }

    @Test
    func fewerRoomsThanKeysLeavesTheRestEmpty() {
        let ordered = visible(rooms(favourites: 1, others: 2), labels: ChatLabelDocument()).ordered
        #expect(ChatListNavigation.shortcutTargets(in: ordered).map(\.id) == ["!fav0", "!room0", "!room1"])
        #expect(ChatListNavigation.shortcutTargets(in: [TestRoom]()).isEmpty)
    }

    // MARK: ⇧⌘] and ⇧⌘[

    private let order = ["!fav", "!a", "!b"]

    @Test
    func nextStepsForwardAndStopsAtTheEnd() {
        #expect(ChatListNavigation.next(after: "!fav", in: order) == "!a")
        #expect(ChatListNavigation.next(after: "!a", in: order) == "!b")
        #expect(ChatListNavigation.next(after: "!b", in: order) == nil)
    }

    @Test
    func nextWithNoVisibleSelectionOpensTheFirstRoom() {
        #expect(ChatListNavigation.next(after: nil, in: order) == "!fav")
        #expect(ChatListNavigation.next(after: "!not-shown", in: order) == "!fav")
        #expect(ChatListNavigation.next(after: nil, in: []) == nil)
    }

    @Test
    func previousStepsBackAndStopsAtTheStart() {
        #expect(ChatListNavigation.previous(before: "!b", in: order) == "!a")
        #expect(ChatListNavigation.previous(before: "!a", in: order) == "!fav")
        #expect(ChatListNavigation.previous(before: "!fav", in: order) == nil)
    }

    @Test
    func previousWithNoVisibleSelectionOpensNothing() {
        #expect(ChatListNavigation.previous(before: nil, in: order) == nil)
        #expect(ChatListNavigation.previous(before: "!not-shown", in: order) == nil)
    }
}

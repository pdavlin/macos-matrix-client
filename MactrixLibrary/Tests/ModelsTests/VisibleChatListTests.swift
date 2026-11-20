import Foundation
@testable import Models
import Testing

/// MATRIX-115: the sidebar's visible rooms and the Go menu's walk over
/// them (D-7c, moved to ⌘] and ⌘[ by MATRIX-217).
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

    // MARK: ⌘] and ⌘[ (MATRIX-217)

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

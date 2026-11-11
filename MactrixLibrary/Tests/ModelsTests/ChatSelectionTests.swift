import Foundation
@testable import Models
import Testing

/// MATRIX-141 Phase B: which chat a window selects when merged chats exist,
/// and what a notification click selects.
struct ChatSelectionTests {
    private static let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"], defaultRoom: "!s2")
    private static let ana = MergedChat(id: "m-ana", name: "Ana", rooms: ["!a1", "!a2"])
    private static let merges = MergedChatDocument(merges: [seth, ana])

    // MARK: Values

    @Test
    func itemIdNamesTheChatListRow() {
        #expect(ChatSelection.room("!r").itemId == "!r")
        #expect(ChatSelection.merged("m-seth").itemId == "m-seth")
        #expect(ChatSelection.room("!r").roomId == "!r")
        #expect(ChatSelection.room("!r").mergedChatId == nil)
        #expect(ChatSelection.merged("m-seth").mergedChatId == "m-seth")
        #expect(ChatSelection.merged("m-seth").roomId == nil)
    }

    @Test
    func chatListItemSelectsItsChat() {
        let entries = [
            ChatListEntry(row: ChatListRowModel(id: "!plain", title: "Plain")),
            ChatListEntry(row: ChatListRowModel(id: "!s1", title: "Seth")),
        ]
        let items = ChatListMerging.items(entries: entries, document: Self.merges)
        #expect(items.map(\.selection) == [.room("!plain"), .merged("m-seth")])
    }

    // MARK: Showing a room

    @Test
    func memberRoomShowsItsMergedChat() {
        #expect(MergedChatSelection.selection(showing: "!s1", document: Self.merges) == .merged("m-seth"))
        #expect(MergedChatSelection.selection(showing: "!a2", document: Self.merges) == .merged("m-ana"))
    }

    @Test
    func roomInNoMergedChatShowsItself() {
        #expect(MergedChatSelection.selection(showing: "!other", document: Self.merges) == .room("!other"))
        #expect(MergedChatSelection.selection(showing: "!s1", document: MergedChatDocument()) == .room("!s1"))
    }

    @Test
    func rowIdOfAMergedChatSelectsIt() {
        #expect(MergedChatSelection.selection(forItemId: "m-seth", document: Self.merges) == .merged("m-seth"))
        #expect(MergedChatSelection.selection(forItemId: "!other", document: Self.merges) == .room("!other"))
        // A member's row never shows, but its ID still maps to the merge.
        #expect(MergedChatSelection.selection(forItemId: "!s2", document: Self.merges) == .merged("m-seth"))
    }

    // MARK: Resolving after a change

    @Test
    func noSelectionStaysEmpty() {
        #expect(MergedChatSelection.resolve(nil, document: Self.merges) == nil)
    }

    @Test
    func selectedMemberRoomMovesToItsMergedChat() {
        // A restored window, a matrix: URL, or a merge of the open DM.
        #expect(MergedChatSelection.resolve(.room("!s1"), document: Self.merges) == .merged("m-seth"))
    }

    @Test
    func selectedPlainRoomStays() {
        #expect(MergedChatSelection.resolve(.room("!other"), document: Self.merges) == .room("!other"))
    }

    @Test
    func selectedMergedChatStaysWhileTheDocumentHoldsIt() {
        let renamed = MergedChatDocument(merges: [MergedChat(id: "m-seth", name: "S", rooms: ["!s1", "!s2", "!s3"])])
        #expect(MergedChatSelection.resolve(.merged("m-seth"), document: renamed, previous: Self.merges) == .merged("m-seth"))
    }

    @Test
    func unmergedChatShowsItsDefaultRoom() {
        let afterUnmerge = MergedChatDocument(merges: [Self.ana])
        #expect(MergedChatSelection.resolve(.merged("m-seth"), document: afterUnmerge, previous: Self.merges) == .room("!s2"))
    }

    @Test
    func unmergedChatWithoutADefaultShowsItsFirstRoom() {
        let afterUnmerge = MergedChatDocument(merges: [Self.seth])
        #expect(MergedChatSelection.resolve(.merged("m-ana"), document: afterUnmerge, previous: Self.merges) == .room("!a1"))
    }

    @Test
    func unmergedChatWhoseDefaultRoomMovedShowsTheNewMergedChat() {
        let moved = MergedChatDocument(merges: [MergedChat(id: "m-new", name: "Seth", rooms: ["!s2", "!s9"])])
        #expect(MergedChatSelection.resolve(.merged("m-seth"), document: moved, previous: Self.merges) == .merged("m-new"))
    }

    @Test
    func restoredMergedChatWaitsForTheFirstRead() {
        // Restored before the merged chats were read: neither document holds
        // it, so the selection stays until the read lands.
        #expect(MergedChatSelection.resolve(.merged("m-seth"), document: MergedChatDocument()) == .merged("m-seth"))
        #expect(MergedChatSelection.resolve(.merged("m-gone"), document: Self.merges, previous: Self.merges) == .merged("m-gone"))
    }

    // MARK: Notification clicks

    @Test
    func notificationFromAMemberSelectsTheMergedChatInAMainWindow() {
        let focus = MergedChatSelection.notificationFocus(roomId: "!s1", singleRoomId: nil, document: Self.merges)
        #expect(focus == .select(.merged("m-seth")))
    }

    @Test
    func notificationFromAPlainRoomSelectsTheRoom() {
        let focus = MergedChatSelection.notificationFocus(roomId: "!other", singleRoomId: nil, document: Self.merges)
        #expect(focus == .select(.room("!other")))
    }

    @Test
    func notificationWithNoMergesSelectsTheRoomAsBefore() {
        let focus = MergedChatSelection.notificationFocus(roomId: "!s1", singleRoomId: nil, document: MergedChatDocument())
        #expect(focus == .select(.room("!s1")))
    }

    @Test
    func roomWindowOfTheNotifiedRoomAlreadyShowsIt() {
        let focus = MergedChatSelection.notificationFocus(roomId: "!s1", singleRoomId: "!s1", document: Self.merges)
        #expect(focus == .alreadyShown)
    }

    @Test
    func roomWindowOfASiblingHandsTheClickToAMainWindow() {
        // The room window shows one member; the merged chat lives in a main
        // window.
        let focus = MergedChatSelection.notificationFocus(roomId: "!s2", singleRoomId: "!s1", document: Self.merges)
        #expect(focus == .bringMainWindowForward)
    }
}

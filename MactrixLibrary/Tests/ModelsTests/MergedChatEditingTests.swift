import Foundation
@testable import Models
import Testing

/// MATRIX-141 Phase B: which chats can merge, what the "Add Chat…" picker
/// offers, and how the Merge Chats sheet writes its draft.
struct MergedChatEditingTests {
    private static let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"])
    private static let ana = MergedChat(id: "m-ana", name: "Ana", rooms: ["!a1", "!a2"])
    private static let merges = MergedChatDocument(merges: [seth, ana])

    // MARK: Room status

    @Test
    func memberRoomIsAMemberWhetherDirectOrNot() {
        #expect(RoomMergeStatus.of(roomId: "!s1", isDirect: true, document: Self.merges) == .member(of: Self.seth))
        #expect(RoomMergeStatus.of(roomId: "!s1", isDirect: false, document: Self.merges) == .member(of: Self.seth))
    }

    @Test
    func oneToOneChatInNoMergeCanMerge() {
        #expect(RoomMergeStatus.of(roomId: "!dm", isDirect: true, document: Self.merges) == .mergeable)
    }

    @Test
    func groupCannotMerge() {
        #expect(RoomMergeStatus.of(roomId: "!group", isDirect: false, document: Self.merges) == .unavailable)
    }

    @Test
    func editorRequestsHaveDistinctIds() {
        #expect(MergedChatEditorRequest.create(roomId: "x").id != MergedChatEditorRequest.edit(mergedChatId: "x").id)
    }

    // MARK: Picker

    @Test
    func pickerOffersOneToOneChatsOutsideTheDraftAndOtherMerges() {
        let draft = MergedChatDraft(name: "Seth", rooms: ["!s1"])
        func isOffered(_ roomId: String, isDirect: Bool = true, editingId: String? = nil) -> Bool {
            MergedChatPicking.offers(roomId: roomId, isDirect: isDirect, draft: draft, editingId: editingId, document: Self.merges)
        }
        #expect(isOffered("!dm"))
        #expect(!isOffered("!group", isDirect: false))
        #expect(!isOffered("!s1"))
        #expect(!isOffered("!a1"))
        // Editing Seth after removing !s2 from the draft: !s2 can come back.
        #expect(isOffered("!s2", editingId: "m-seth"))
        // A new merged chat does not take !s2 from Seth.
        #expect(!isOffered("!s2"))
    }

    // MARK: Writing the draft

    @Test
    func newDraftCreatesTheMergedChat() throws {
        var doc = Self.merges
        let draft = MergedChatDraft(name: "  Bo  ", rooms: ["!b1", "!b2"], defaultRoom: "!b2", avatarRoom: "!b1")
        let applied = doc.apply(draft, to: "m-bo")
        #expect(applied)
        let created = try #require(doc.merge(id: "m-bo"))
        #expect(created == MergedChat(id: "m-bo", name: "Bo", rooms: ["!b1", "!b2"], defaultRoom: "!b2", avatarRoom: "!b1"))
        #expect(doc.merges.count == 3)
        #expect(doc.holds(draft, as: "m-bo"))
    }

    @Test
    func editDraftReplacesMembersNameAndChoices() throws {
        var doc = MergedChatDocument(merges: [
            MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"], defaultRoom: "!s1", avatarRoom: "!s2"),
        ])
        let draft = MergedChatDraft(name: "Seth R", rooms: ["!s1", "!s3"], defaultRoom: "!s3")
        let applied = doc.apply(draft, to: "m-seth")
        #expect(applied)
        let edited = try #require(doc.merge(id: "m-seth"))
        #expect(edited == MergedChat(id: "m-seth", name: "Seth R", rooms: ["!s1", "!s3"], defaultRoom: "!s3", avatarRoom: nil))
        #expect(doc.holds(draft, as: "m-seth"))
    }

    @Test
    func editOfAMergeRemovedElsewhereCreatesItAgain() throws {
        var doc = MergedChatDocument(merges: [Self.ana])
        let draft = MergedChatDraft(merge: Self.seth)
        let applied = doc.apply(draft, to: "m-seth")
        #expect(applied)
        #expect(try #require(doc.merge(id: "m-seth")).rooms == ["!s1", "!s2"])
    }

    @Test
    func draftWithOneChatIsRefusedAndChangesNothing() {
        var doc = Self.merges
        let draft = MergedChatDraft(name: "Seth", rooms: ["!s1"])
        let appliedToExisting = doc.apply(draft, to: "m-seth")
        let appliedToNew = doc.apply(draft, to: "m-new")
        #expect(!appliedToExisting)
        #expect(!appliedToNew)
        #expect(doc == Self.merges)
        #expect(!doc.holds(draft, as: "m-seth"))
    }

    @Test
    func holdsIsFalseUntilTheDocumentMatches() {
        let draft = MergedChatDraft(name: "Seth", rooms: ["!s1", "!s2", "!s3"])
        #expect(!Self.merges.holds(draft, as: "m-seth"))
        #expect(!MergedChatDocument().holds(draft, as: "m-seth"))
    }
}

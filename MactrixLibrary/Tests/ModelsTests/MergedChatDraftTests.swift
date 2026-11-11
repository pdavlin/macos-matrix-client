@testable import Models
import Testing

/// MATRIX-141: the Merge Chats sheet's draft.
struct MergedChatDraftTests {
    @Test
    func initDropsRepeatedRooms() {
        let draft = MergedChatDraft(name: "Seth", rooms: ["!a", "!b", "!a"])
        #expect(draft.rooms == ["!a", "!b"])
    }

    @Test
    func initFromChatsPrefillsTheFirstTitle() {
        let draft = MergedChatDraft(chats: [
            ChatListRowModel(id: "!a", title: "Seth Redacted"),
            ChatListRowModel(id: "!b", title: "Seth R."),
        ])
        #expect(draft.name == "Seth Redacted")
        #expect(draft.rooms == ["!a", "!b"])
        #expect(MergedChatDraft(chats: []).name.isEmpty)
    }

    @Test
    func initFromAMergeKeepsItsChoices() {
        let merge = MergedChat(id: "m", name: "Seth", rooms: ["!a", "!b"], defaultRoom: "!b", avatarRoom: "!a")
        let draft = MergedChatDraft(merge: merge)
        #expect(draft == MergedChatDraft(name: "Seth", rooms: ["!a", "!b"], defaultRoom: "!b", avatarRoom: "!a"))
        #expect(draft.mergedChat(id: "m") == merge)
    }

    @Test
    func submitNeedsANameAndTwoChats() {
        #expect(MergedChatDraft(name: "Seth", rooms: ["!a", "!b"]).canSubmit)
        #expect(!MergedChatDraft(name: "Seth", rooms: ["!a"]).canSubmit)
        #expect(!MergedChatDraft(name: "  \n", rooms: ["!a", "!b"]).canSubmit)
        #expect(!MergedChatDraft(name: "Seth").canSubmit)
    }

    @Test
    func addKeepsAnExistingChatInPlace() {
        var draft = MergedChatDraft(rooms: ["!a", "!b"])
        draft.add("!a")
        draft.add("!c")
        #expect(draft.rooms == ["!a", "!b", "!c"])
    }

    @Test
    func removeResetsChoicesThatPointedAtTheChat() {
        var draft = MergedChatDraft(name: "Seth", rooms: ["!a", "!b", "!c"], defaultRoom: "!b", avatarRoom: "!b")
        draft.remove("!b")
        #expect(draft.rooms == ["!a", "!c"])
        #expect(draft.defaultRoom == nil)
        #expect(draft.avatarRoom == nil)

        var other = MergedChatDraft(rooms: ["!a", "!b"], defaultRoom: "!a", avatarRoom: "!a")
        other.remove("!b")
        #expect(other.defaultRoom == "!a")
        #expect(other.avatarRoom == "!a")
    }

    @Test
    func effectiveDefaultRoomFallsBackToTheFirstChat() {
        #expect(MergedChatDraft(rooms: ["!a", "!b"], defaultRoom: "!b").effectiveDefaultRoom == "!b")
        #expect(MergedChatDraft(rooms: ["!a", "!b"]).effectiveDefaultRoom == "!a")
        #expect(MergedChatDraft(rooms: ["!a", "!b"], defaultRoom: "!gone").effectiveDefaultRoom == "!a")
        #expect(MergedChatDraft().effectiveDefaultRoom == nil)
    }

    @Test
    func effectiveAvatarRoomFollowsTheChatListRule() {
        let hasImage: (String) -> Bool = { $0 == "!c" }
        #expect(MergedChatDraft(rooms: ["!a", "!b", "!c"], avatarRoom: "!b").effectiveAvatarRoom(hasAvatar: hasImage) == "!b")
        #expect(MergedChatDraft(rooms: ["!a", "!b", "!c"]).effectiveAvatarRoom(hasAvatar: hasImage) == "!c")
        #expect(MergedChatDraft(rooms: ["!a", "!b"]).effectiveAvatarRoom(hasAvatar: hasImage) == "!a")
        #expect(MergedChatDraft(rooms: ["!a", "!b"], avatarRoom: "!gone").effectiveAvatarRoom(hasAvatar: hasImage) == "!a")
        #expect(MergedChatDraft().effectiveAvatarRoom(hasAvatar: hasImage) == nil)
    }

    @Test
    func mergedChatTrimsTheNameAndDropsStaleChoices() {
        var draft = MergedChatDraft(name: "  Seth ", rooms: ["!a", "!b"])
        draft.defaultRoom = "!gone"
        draft.avatarRoom = "!b"
        let merge = draft.mergedChat(id: "m")
        #expect(merge == MergedChat(id: "m", name: "Seth", rooms: ["!a", "!b"], defaultRoom: nil, avatarRoom: "!b"))
    }

    @Test
    func memberLabelsNameTheNetworkAndNumberRepeats() {
        let labels = MergedChatDraft.memberLabels(for: [
            ChatListRowModel(id: "!a", title: "Seth", network: .slack),
            ChatListRowModel(id: "!b", title: "Seth", network: .slack),
            ChatListRowModel(id: "!c", title: "Seth"),
            ChatListRowModel(id: "!d", title: "Seth", network: .googleChat),
            ChatListRowModel(id: "!e", title: "Seth", network: .slack),
        ])
        #expect(labels == ["Seth · Slack", "Seth · Slack (2)", "Seth", "Seth · Google Chat", "Seth · Slack (3)"])
    }
}

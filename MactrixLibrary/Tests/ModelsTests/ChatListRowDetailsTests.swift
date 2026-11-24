import Foundation
@testable import Models
import Testing

/// MATRIX-224: the draft and typing lines of a chat-list row, and the
/// Drafts filter.
struct ChatListRowDetailsTests {
    // MARK: Draft text

    @Test
    func newMessageDraftShowsItsText() {
        #expect(ChatListDraftText.previewText(draftText: "See you at six", kind: .newMessage) == "See you at six")
    }

    @Test
    func replyDraftShowsItsText() {
        #expect(ChatListDraftText.previewText(draftText: "Yes", kind: .reply) == "Yes")
    }

    @Test
    func editDraftShowsNoDraft() {
        #expect(ChatListDraftText.previewText(draftText: "Fixed typo", kind: .edit) == nil)
    }

    @Test
    func replyWithAnEmptyComposerShowsNoDraft() {
        #expect(ChatListDraftText.previewText(draftText: "", kind: .reply) == nil)
        #expect(ChatListDraftText.previewText(draftText: " \n  ", kind: .newMessage) == nil)
    }

    @Test
    func draftLinesJoinIntoOne() {
        #expect(ChatListDraftText.previewText(draftText: "First line\n\n  second line ", kind: .newMessage) == "First line second line")
    }

    @Test
    func mentionChipReadsAsItsLabel() {
        let draft = "Hi [Alex Kim](https://matrix.to/#/@alex:example.org), lunch?"
        #expect(ChatListDraftText.previewText(draftText: draft, kind: .newMessage) == "Hi @Alex Kim, lunch?")
    }

    // MARK: Typing text

    @Test
    func nobodyTypingShowsNoTypingState() {
        #expect(ChatListTypingText.text(names: [], isDirect: false) == nil)
        #expect(ChatListTypingText.text(names: [], isDirect: true) == nil)
    }

    @Test
    func directChatDoesNotRepeatTheName() {
        #expect(ChatListTypingText.text(names: ["Alex"], isDirect: true) == "typing…")
    }

    @Test(arguments: [
        (["Alex"], "Alex is typing…"),
        (["Alex", "Sam"], "Alex and Sam are typing…"),
        (["Alex", "Sam", "Kim"], "Alex and 2 others are typing…"),
    ])
    func groupNamesThePeople(names: [String], expected: String) {
        #expect(ChatListTypingText.text(names: names, isDirect: false) == expected)
    }

    // MARK: The second line

    private func row(isDirect: Bool = false) -> ChatListRowModel {
        ChatListRowModel(id: "!a", title: "Alex", isDirect: isDirect, preview: "Alex: Lunch?")
    }

    @Test
    func previewShowsWithoutDraftOrTyping() {
        #expect(row().previewLine == .preview("Alex: Lunch?"))
        #expect(row().previewLine.spokenText == "Alex: Lunch?")
    }

    @Test
    func draftReplacesThePreview() {
        var model = row()
        model.draft = "On my way"
        #expect(model.previewLine == .draft("On my way"))
        #expect(model.previewLine.spokenText == "Draft: On my way")
    }

    @Test
    func typingGoesBeforeTheDraft() {
        var model = row()
        model.draft = "On my way"
        model.typingNames = ["Alex"]
        #expect(model.previewLine == .typing("Alex is typing…"))
    }

    @Test
    func inboxNoteGoesBeforeEverything() {
        var model = row()
        model.draft = "On my way"
        model.typingNames = ["Alex"]
        model.inboxNote = "Snoozed until tomorrow 9:00 AM"
        #expect(model.previewLine == .inboxNote("Snoozed until tomorrow 9:00 AM"))
    }

    // MARK: Drafts on the visible list

    private static let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"])
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func visible(_ ids: [String]) -> VisibleChatList<ChatListItem> {
        let entries = ids.enumerated().map { index, id in
            ChatListEntry(
                row: ChatListRowModel(id: id, title: "Title \(id)"),
                lastActivity: Self.base.addingTimeInterval(-Double(index) * 60)
            )
        }
        return ChatListMerging.visible(entries: entries, document: MergedChatDocument(merges: [Self.seth]))
    }

    @Test
    func roomDraftGoesOnItsRow() {
        let list = visible(["!a", "!b"]).withDrafts(ChatListDrafts(rooms: ["!b": "Later"]))
        #expect(list.ordered.map(\.row.draft) == [nil, "Later"])
    }

    @Test
    func mergedChatShowsOnlyTheMergedDraft() {
        let memberDraftOnly = visible(["!s1", "!s2"]).withDrafts(ChatListDrafts(rooms: ["!s1": "Member draft"]))
        #expect(memberDraftOnly.ordered.map(\.row.draft) == [nil])

        let mergedDraft = visible(["!s1", "!s2"]).withDrafts(ChatListDrafts(merges: ["m-seth": "Merged draft"]))
        #expect(mergedDraft.ordered.map(\.row.draft) == ["Merged draft"])
    }

    @Test
    func draftsFilterKeepsTheChatsWithADraft() {
        let list = visible(["!a", "!b", "!s1", "!c"])
            .withDrafts(ChatListDrafts(rooms: ["!b": "Later", "!c": "Soon"], merges: ["m-seth": "Hey"]))
            .filtered(for: .drafts)
        #expect(list.ordered.map(\.id) == ["!b", "m-seth", "!c"])
    }

    @Test
    func draftsNarrowingNamesTheMergedMembers() {
        let drafts = ChatListDrafts(rooms: ["!a": "x"], merges: ["m-seth": "y", "m-gone": "z"])
        #expect(drafts.roomIds(merges: MergedChatDocument(merges: [Self.seth])) == ["!a", "!s1", "!s2"])
    }

    // MARK: Typing on the visible list

    @Test
    func typingGoesOnTheRowsOfItsRooms() {
        let list = visible(["!a", "!b"]).withTyping(["!b": ["Sam"]])
        #expect(list.ordered.map(\.row.typingNames) == [[], ["Sam"]])
    }

    @Test
    func mergedChatShowsEveryMembersTypingOneTime() {
        let list = visible(["!s1", "!s2"]).withTyping(["!s1": ["Seth"], "!s2": ["Seth", "Ana"]])
        #expect(list.ordered.map(\.row.typingNames) == [["Seth", "Ana"]])
    }

    // MARK: The filters

    @Test
    func newFiltersRefineTheInbox() {
        for filter in [ChatListFilter.unanswered, .drafts] {
            #expect(filter.inboxPlacement == .inbox)
            #expect(!filter.title.isEmpty)
            #expect(!filter.systemImage.isEmpty)
        }
        #expect(ChatListFilter.unanswered.title == "Unanswered")
        #expect(ChatListFilter.drafts.title == "Drafts")
    }

    @Test
    func onlyArchivedSnoozedAndDraftsNarrowByRoomIds() {
        let narrowed = ChatListFilter.allCases.filter(\.narrowsByRoomIds)
        #expect(narrowed == [.drafts, .archived, .snoozed])
    }
}

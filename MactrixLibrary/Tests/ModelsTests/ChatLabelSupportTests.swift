import Foundation
@testable import Models
import Testing

/// MATRIX-77: the edit-sheet Save rule, the rail badge, and the write-echo
/// gate.
struct ChatLabelSupportTests {
    // MARK: Draft

    @Test
    func newLabelNeedsANameAndAChat() {
        let original = ChatLabelDraft()
        #expect(!ChatLabelDraft(name: "Work").canSave(comparedTo: original))
        #expect(!ChatLabelDraft(name: "   ", rooms: ["!a"]).canSave(comparedTo: original))
        #expect(ChatLabelDraft(name: "Work", rooms: ["!a"]).canSave(comparedTo: original))
    }

    @Test
    func preselectedChatIsNotEnoughWithoutAName() {
        let original = ChatLabelDraft(rooms: ["!a"])
        #expect(!original.canSave(comparedTo: original))
        #expect(ChatLabelDraft(name: "Work", rooms: ["!a"]).canSave(comparedTo: original))
    }

    @Test
    func editNeedsAChange() {
        let original = ChatLabelDraft(label: ChatLabel(name: "Work", colorIndex: 1, icon: "star", rooms: ["!a", "!b"]))
        var draft = original
        #expect(!draft.canSave(comparedTo: original))
        draft.name = " Work "
        #expect(!draft.canSave(comparedTo: original))
        draft.rooms = ["!b", "!a"]
        #expect(!draft.canSave(comparedTo: original))
        draft.colorIndex = 2
        #expect(draft.canSave(comparedTo: original))
        draft = original
        draft.icon = nil
        #expect(draft.canSave(comparedTo: original))
        draft = original
        draft.toggle("!a")
        #expect(draft.rooms == ["!b"])
        #expect(draft.canSave(comparedTo: original))
        draft.toggle("!b")
        #expect(!draft.canSave(comparedTo: original))
    }

    // MARK: Badge

    private let label = ChatLabel(id: "l", name: "L", rooms: ["!a", "!b", "!c"])

    @Test
    func readLabelHasNoBadge() {
        #expect(ChatLabelBadge.badge(for: label, unread: [:]) == .none)
        #expect(ChatLabelBadge.badge(for: label, unread: ["!a": ChatListUnread()]) == .none)
    }

    @Test
    func countsUnreadUnmutedChats() {
        let unread: [String: ChatListUnread] = [
            "!a": ChatListUnread(count: 4, isUnread: true),
            "!b": ChatListUnread(count: 1, isUnread: true),
            "!c": ChatListUnread(count: 9, isUnread: true, isMuted: true),
            "!elsewhere": ChatListUnread(count: 2, isUnread: true),
        ]
        #expect(ChatLabelBadge.badge(for: label, unread: unread) == .count(2))
    }

    @Test
    func mutedOrMarkedActivityIsADot() {
        #expect(ChatLabelBadge.badge(for: label, unread: ["!a": ChatListUnread(count: 3, isUnread: true, isMuted: true)]) == .dot)
        #expect(ChatLabelBadge.badge(for: label, unread: ["!b": ChatListUnread(isUnread: true)]) == .dot)
    }

    @Test
    func mutedLabelShowsAtMostADot() {
        var muted = label
        muted.isMuted = true
        #expect(ChatLabelBadge.badge(for: muted, unread: ["!a": ChatListUnread(count: 3, isUnread: true)]) == .dot)
    }

    @Test
    func badgeDescriptions() {
        #expect(ChatLabelBadge.none.accessibilityDescription == nil)
        #expect(ChatLabelBadge.dot.accessibilityDescription == "unread activity")
        #expect(ChatLabelBadge.count(1).accessibilityDescription == "1 unread chat")
        #expect(ChatLabelBadge.count(3).accessibilityDescription == "3 unread chats")
    }

    // MARK: Row mute

    @Test
    func labelMuteMarksTheRowMuted() {
        let unread = ChatListUnread(
            numUnreadMessages: 1,
            numUnreadNotifications: 1,
            numUnreadMentions: 0,
            isMarkedUnread: false,
            isMuted: false,
            isMutedByLabel: true
        )
        #expect(unread.isMuted)
        #expect(unread.isMutedByLabel)
        let row = ChatListRowModel(id: "!a", title: "Alice", unread: unread)
        #expect(row.helpText == "Alice\nMuted by Label")
        #expect(row.accessibilityLabel == "Alice, 1 unread message, muted by label")
    }

    @Test
    func ownMuteWinsOverLabelMute() {
        let unread = ChatListUnread(
            numUnreadMessages: 0,
            numUnreadNotifications: 0,
            numUnreadMentions: 0,
            isMarkedUnread: false,
            isMuted: true,
            isMutedByLabel: true
        )
        #expect(unread.isMuted)
        #expect(!unread.isMutedByLabel)
        #expect(ChatListRowModel(id: "!a", title: "Alice", unread: unread).helpText == "Alice")
    }

    // MARK: Echo gate

    private func document(_ name: String) -> ChatLabelDocument {
        ChatLabelDocument(labels: [ChatLabel(id: "x", name: name)])
    }

    @Test
    func readsPassThroughWithNoPendingWrite() {
        var gate = ChatLabelEchoGate()
        let read = ChatLabelReadResult.parsed(document("A"))
        #expect(gate.accept(read) == read)
        #expect(gate.pendingDocument() == nil)
    }

    @Test
    func staleReadIsHeldUntilTheEchoArrives() {
        let start = Date(timeIntervalSince1970: 1000)
        var gate = ChatLabelEchoGate(timeout: 30)
        gate.didWrite(document("B"), now: start)
        #expect(gate.accept(.parsed(document("A")), now: start.addingTimeInterval(1)) == nil)
        #expect(gate.pendingDocument(now: start.addingTimeInterval(2)) == document("B"))
        #expect(gate.accept(.parsed(document("B")), now: start.addingTimeInterval(3)) == .parsed(document("B")))
        #expect(gate.pendingDocument(now: start.addingTimeInterval(4)) == nil)
        #expect(gate.accept(.parsed(document("C")), now: start.addingTimeInterval(5)) == .parsed(document("C")))
    }

    @Test
    func pendingWriteExpires() {
        let start = Date(timeIntervalSince1970: 1000)
        var gate = ChatLabelEchoGate(timeout: 30)
        gate.didWrite(document("B"), now: start)
        #expect(gate.pendingDocument(now: start.addingTimeInterval(31)) == nil)
        gate.didWrite(document("B"), now: start)
        #expect(gate.accept(.parsed(document("C")), now: start.addingTimeInterval(31)) == .parsed(document("C")))
    }

    @Test
    func laterWriteReplacesThePendingOne() {
        let start = Date(timeIntervalSince1970: 1000)
        var gate = ChatLabelEchoGate(timeout: 30)
        gate.didWrite(document("B"), now: start)
        gate.didWrite(document("C"), now: start.addingTimeInterval(1))
        // The first write's echo is now stale too.
        #expect(gate.accept(.parsed(document("B")), now: start.addingTimeInterval(2)) == nil)
        #expect(gate.accept(.parsed(document("C")), now: start.addingTimeInterval(3)) == .parsed(document("C")))
    }
}

import Foundation
import Models
import Testing

/// MATRIX-144: a notification from a member room of a merged chat shows as
/// the merged chat.
struct MergedNotificationRemapTests {
    private let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!slack1", "!slack2"])

    // MARK: Rooms that are not merged

    /// The format of before MATRIX-144: `"<sender> (<room name>)"`.
    @Test func unmergedRoomKeepsTodaysTitle() {
        let remap = MergedNotificationRemap.remap(
            roomId: "!group",
            roomDisplayName: "Pizza Box Audit Committee",
            senderDisplayName: "Seth",
            document: MergedChatDocument(merges: [seth])
        )
        #expect(remap.title == "Seth (Pizza Box Audit Committee)")
        #expect(remap.threadIdentifier == nil)
        #expect(remap.avatarRoomCandidates == ["!group"])
        #expect(remap.mergedChatId == nil)
    }

    /// The default lookup is an empty document: no notification changes.
    @Test func emptyDocumentChangesNothing() {
        let remap = MergedNotificationRemap.remap(
            roomId: "!slack1",
            roomDisplayName: "Seth Smith",
            senderDisplayName: "Seth Smith",
            document: MergedChatDocument()
        )
        #expect(remap == MergedNotificationRemap(
            title: "Seth Smith (Seth Smith)",
            threadIdentifier: nil,
            avatarRoomCandidates: ["!slack1"],
            mergedChatId: nil
        ))
    }

    @Test func titleFormat() {
        #expect(MergedNotificationRemap.title(senderDisplayName: "@seth:davlin.io", chatName: "DM") == "@seth:davlin.io (DM)")
    }

    // MARK: Member rooms

    @Test(arguments: ["!slack1", "!slack2"])
    func memberShowsMergedChatName(roomId: String) {
        let remap = MergedNotificationRemap.remap(
            roomId: roomId,
            roomDisplayName: "Seth Smith (DevObsessed)",
            senderDisplayName: "Seth Smith",
            document: MergedChatDocument(merges: [seth])
        )
        #expect(remap.title == "Seth Smith (Seth)")
        #expect(remap.mergedChatId == "m-seth")
    }

    /// Every member uses the merged chat's ID, so macOS stacks them together.
    @Test func membersShareOneThreadIdentifier() {
        let document = MergedChatDocument(merges: [seth])
        let first = MergedNotificationRemap.remap(roomId: "!slack1", roomDisplayName: "a", senderDisplayName: "s", document: document)
        let second = MergedNotificationRemap.remap(roomId: "!slack2", roomDisplayName: "b", senderDisplayName: "s", document: document)
        #expect(first.threadIdentifier == "m-seth")
        #expect(second.threadIdentifier == first.threadIdentifier)
    }

    /// A merged chat with a blank name shows the member room's own name.
    @Test(arguments: ["", "  \n"])
    func blankMergedNameFallsBackToRoomName(name: String) {
        let merge = MergedChat(id: "m1", name: name, rooms: ["!a", "!b"])
        let remap = MergedNotificationRemap.remap(
            roomId: "!b",
            roomDisplayName: "Room B",
            senderDisplayName: "Seth",
            document: MergedChatDocument(merges: [merge])
        )
        #expect(remap.title == "Seth (Room B)")
        #expect(remap.threadIdentifier == "m1")
    }

    @Test func mergedNameIsTrimmed() {
        let merge = MergedChat(id: "m1", name: " Seth ", rooms: ["!a", "!b"])
        #expect(remap(roomId: "!a", sender: "Seth", merge: merge).title == "Seth (Seth)")
    }

    /// Only the merged chat that holds the room applies.
    @Test func picksTheMergeThatHoldsTheRoom() {
        let other = MergedChat(id: "m-ana", name: "Ana", rooms: ["!ana1", "!ana2"])
        let remap = MergedNotificationRemap.remap(
            roomId: "!ana2",
            roomDisplayName: "x",
            senderDisplayName: "Ana",
            document: MergedChatDocument(merges: [seth, other])
        )
        #expect(remap.title == "Ana (Ana)")
        #expect(remap.threadIdentifier == "m-ana")
    }

    // MARK: Avatar

    /// No explicit avatar room: every member in order, so the caller shows
    /// the first member with an avatar.
    @Test func avatarCandidatesWithoutAvatarRoom() {
        let merge = MergedChat(id: "m1", name: "Seth", rooms: ["!a", "!b", "!c"])
        #expect(remap(roomId: "!c", merge: merge).avatarRoomCandidates == ["!a", "!b", "!c"])
    }

    @Test func avatarRoomComesFirst() {
        let merge = MergedChat(id: "m1", name: "Seth", rooms: ["!a", "!b", "!c"], avatarRoom: "!b")
        #expect(remap(roomId: "!a", merge: merge).avatarRoomCandidates == ["!b", "!a", "!c"])
    }

    /// An avatar room that left the merge is ignored.
    @Test func staleAvatarRoomIsIgnored() {
        let merge = MergedChat(id: "m1", name: "Seth", rooms: ["!a", "!b"], avatarRoom: "!gone")
        #expect(remap(roomId: "!a", merge: merge).avatarRoomCandidates == ["!a", "!b"])
    }

    /// A remap from a document that holds only `merge`.
    private func remap(roomId: String, sender: String = "s", merge: MergedChat) -> MergedNotificationRemap {
        MergedNotificationRemap.remap(
            roomId: roomId,
            roomDisplayName: "x",
            senderDisplayName: sender,
            document: MergedChatDocument(merges: [merge])
        )
    }

    // MARK: Mute

    /// A member follows its own label mute (orchestrator decision
    /// 2026-11-10): the merge does not change the decision, so a label-muted
    /// member does not post even when its sibling is not muted.
    @Test(arguments: [false, true])
    func memberFollowsItsOwnLabelMute(isMutedByLabel: Bool) {
        let decision = NotificationDecision.decide(isMutedByLabel: isMutedByLabel, settings: NotificationPreferences())
        #expect(decision == (isMutedByLabel ? .suppress(.mutedByLabel) : .post(playsSound: true)))
    }
}

/// MATRIX-144: a merged chat counts once on the Dock badge.
struct MergedDockBadgeTests {
    private let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!slack1", "!slack2"])

    @Test func mergedChatWithSeveralUnreadMembersCountsOnce() {
        let chats = [
            UnreadChatState(roomId: "!slack1", numUnreadMessages: 3, isDirect: true),
            UnreadChatState(roomId: "!slack2", numUnreadMessages: 5, isDirect: true),
            UnreadChatState(roomId: "!other", numUnreadNotifications: 1),
        ]
        let count = DockBadge.unreadChatCount(chats, labelMutedRoomIds: [], mergedChats: MergedChatDocument(merges: [seth]))
        #expect(count == 2)
    }

    @Test func mergedChatWithOneUnreadMemberCountsOnce() {
        let chats = [
            UnreadChatState(roomId: "!slack1", isDirect: true),
            UnreadChatState(roomId: "!slack2", numUnreadMessages: 1, isDirect: true),
        ]
        #expect(DockBadge.unreadChatCount(chats, labelMutedRoomIds: [], mergedChats: MergedChatDocument(merges: [seth])) == 1)
    }

    @Test func readMergedChatDoesNotCount() {
        let chats = [
            UnreadChatState(roomId: "!slack1", isDirect: true),
            UnreadChatState(roomId: "!slack2", isDirect: true),
        ]
        #expect(DockBadge.unreadChatCount(chats, labelMutedRoomIds: [], mergedChats: MergedChatDocument(merges: [seth])) == 0)
    }

    /// Each member follows its own mute: a muted member adds nothing, an
    /// unmuted sibling still counts the merged chat.
    @Test func mutedMemberDoesNotCountButSiblingDoes() {
        let chats = [
            UnreadChatState(roomId: "!slack1", numUnreadMessages: 4, isDirect: true, isMuted: true),
            UnreadChatState(roomId: "!slack2", numUnreadMessages: 1, isDirect: true),
        ]
        #expect(DockBadge.unreadChatCount(chats, labelMutedRoomIds: [], mergedChats: MergedChatDocument(merges: [seth])) == 1)
        #expect(DockBadge.unreadChatCount(chats, labelMutedRoomIds: ["!slack2"], mergedChats: MergedChatDocument(merges: [seth])) == 0)
    }

    /// A merged chat is muted when every member is muted; it never counts.
    @Test func fullyMutedMergedChatNeverCounts() {
        let chats = [
            UnreadChatState(roomId: "!slack1", numUnreadNotifications: 2, isDirect: true, isMuted: true),
            UnreadChatState(roomId: "!slack2", numUnreadNotifications: 2, isDirect: true, isMuted: true),
        ]
        #expect(DockBadge.unreadChatCount(chats, labelMutedRoomIds: [], mergedChats: MergedChatDocument(merges: [seth])) == 0)
    }

    @Test func twoMergedChatsCountSeparately() {
        let ana = MergedChat(id: "m-ana", name: "Ana", rooms: ["!ana1", "!ana2"])
        let chats = [
            UnreadChatState(roomId: "!slack1", isMarkedUnread: true),
            UnreadChatState(roomId: "!slack2", isMarkedUnread: true),
            UnreadChatState(roomId: "!ana1", numUnreadNotifications: 1),
            UnreadChatState(roomId: "!ana2", numUnreadNotifications: 1),
        ]
        #expect(DockBadge.unreadChatCount(chats, labelMutedRoomIds: [], mergedChats: MergedChatDocument(merges: [seth, ana])) == 2)
    }

    /// A merged member that is not in the room list (left, or not synced yet)
    /// adds nothing.
    @Test func missingMemberIsIgnored() {
        let chats = [UnreadChatState(roomId: "!slack1", numUnreadNotifications: 1)]
        #expect(DockBadge.unreadChatCount(chats, labelMutedRoomIds: [], mergedChats: MergedChatDocument(merges: [seth])) == 1)
    }

    /// The default lookup is an empty document: the count equals MATRIX-119's.
    @Test func emptyDocumentMatchesTheUnmergedCount() {
        let chats = [
            UnreadChatState(roomId: "!dm", numUnreadNotifications: 12, numUnreadMessages: 12, isDirect: true),
            UnreadChatState(roomId: "!group", numUnreadNotifications: 40, numUnreadMessages: 40),
            UnreadChatState(roomId: "!marked", isMarkedUnread: true),
            UnreadChatState(roomId: "!read"),
            UnreadChatState(roomId: "!muted", numUnreadNotifications: 9, isMuted: true),
            UnreadChatState(roomId: "!labelMuted", numUnreadNotifications: 9),
        ]
        let merged = DockBadge.unreadChatCount(chats, labelMutedRoomIds: ["!labelMuted"], mergedChats: MergedChatDocument())
        #expect(merged == DockBadge.unreadChatCount(chats, labelMutedRoomIds: ["!labelMuted"]))
        #expect(merged == 3)
    }
}

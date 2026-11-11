import Foundation
import Models
import Testing

/// MATRIX-143 Phase B: the merged composer's target memory, the composer
/// mode, the typing notices, and the Up-arrow edit room.
struct MergedComposerTargetingTests {
    private static let roomA = "!a:davlin.io"
    private static let roomB = "!b:davlin.io"
    private static let merge = MergedChat(id: "seth", name: "Seth", rooms: [roomA, roomB], defaultRoom: roomA)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func ago(minutes: Double) -> Date {
        now.addingTimeInterval(-minutes * 60)
    }

    private static func theirs(minutes: Double) -> MergedSendTarget.RoomActivity {
        .init(newestMessageAt: ago(minutes: minutes))
    }

    private static func own(minutes: Double) -> MergedSendTarget.RoomActivity {
        .init(newestMessageAt: ago(minutes: minutes), newestOwnMessageAt: ago(minutes: minutes))
    }

    private static func updated(
        _ targeting: MergedComposerTargeting = MergedComposerTargeting(),
        activity: [String: MergedSendTarget.RoomActivity],
        manualPick: String? = nil,
        hasContent: Bool = false,
        at time: Date = now
    ) -> MergedComposerTargeting {
        var copy = targeting
        copy.update(merge: merge, activity: activity, manualPick: manualPick, composerHasContent: hasContent, now: time)
        return copy
    }

    // MARK: - Update and stabilization

    @Test func startsWithNoTarget() {
        let targeting = MergedComposerTargeting()
        #expect(targeting.newMessageTarget == nil)
        #expect(targeting.target(for: .newMessage, rooms: Self.merge.rooms) == nil)
    }

    /// Seth's case: he wrote last in B, so the answer goes to B.
    @Test func followsTheNewestMessage() {
        let targeting = Self.updated(activity: [Self.roomA: Self.own(minutes: 180), Self.roomB: Self.theirs(minutes: 5)])
        #expect(targeting.newMessageTarget == MergedSendTarget(roomId: Self.roomB, reason: .recentActivity))
    }

    @Test func emptyComposerFollowsNewActivity() {
        let first = Self.updated(activity: [Self.roomB: Self.theirs(minutes: 5)])
        let second = Self.updated(first, activity: [Self.roomA: Self.theirs(minutes: 1), Self.roomB: Self.theirs(minutes: 5)])
        #expect(second.newMessageTarget == MergedSendTarget(roomId: Self.roomA, reason: .recentActivity))
    }

    @Test func composerWithContentKeepsItsTarget() {
        let first = Self.updated(activity: [Self.roomB: Self.theirs(minutes: 5)], hasContent: true)
        let second = Self.updated(
            first,
            activity: [Self.roomA: Self.theirs(minutes: 1), Self.roomB: Self.theirs(minutes: 5)],
            hasContent: true
        )
        #expect(second.newMessageTarget == MergedSendTarget(roomId: Self.roomB, reason: .recentActivity))
    }

    @Test func emptyingTheComposerReleasesTheTarget() {
        let first = Self.updated(activity: [Self.roomB: Self.theirs(minutes: 5)], hasContent: true)
        let activity = [Self.roomA: Self.theirs(minutes: 1), Self.roomB: Self.theirs(minutes: 5)]
        let kept = Self.updated(first, activity: activity, hasContent: true)
        let released = Self.updated(kept, activity: activity, hasContent: false)
        #expect(released.newMessageTarget == MergedSendTarget(roomId: Self.roomA, reason: .recentActivity))
    }

    /// A saved draft opens the composer with content. While a member room
    /// has not loaded, the target follows the activity as it arrives.
    @Test func contentDoesNotKeepTheTargetWhileActivityIsUnknown() {
        var targeting = MergedComposerTargeting()
        targeting.update(
            merge: Self.merge,
            activity: [Self.roomA: Self.own(minutes: 180)],
            manualPick: nil,
            composerHasContent: true,
            activityIsKnown: false,
            now: Self.now
        )
        #expect(targeting.newMessageTarget == MergedSendTarget(roomId: Self.roomA, reason: .defaultRoom))
        targeting.update(
            merge: Self.merge,
            activity: [Self.roomA: Self.own(minutes: 180), Self.roomB: Self.theirs(minutes: 5)],
            manualPick: nil,
            composerHasContent: true,
            activityIsKnown: true,
            now: Self.now
        )
        #expect(targeting.newMessageTarget == MergedSendTarget(roomId: Self.roomB, reason: .recentActivity))
    }

    @Test func manualPickWinsEvenWithContent() {
        let first = Self.updated(activity: [Self.roomB: Self.theirs(minutes: 5)], hasContent: true)
        let picked = Self.updated(first, activity: [Self.roomB: Self.theirs(minutes: 5)], manualPick: Self.roomA, hasContent: true)
        #expect(picked.newMessageTarget == MergedSendTarget(roomId: Self.roomA, reason: .chosen))
    }

    @Test func choosingAutomaticallyAfterAPickResolvesAgain() {
        let activity = [Self.roomB: Self.theirs(minutes: 5)]
        let picked = Self.updated(activity: activity, manualPick: Self.roomA, hasContent: true)
        let automatic = Self.updated(picked, activity: activity, manualPick: nil, hasContent: true)
        #expect(automatic.newMessageTarget == MergedSendTarget(roomId: Self.roomB, reason: .recentActivity))
    }

    /// The own last message turns old while the composer is empty, so the
    /// target moves to the default room.
    @Test func oldOwnMessageMovesAnEmptyComposerToTheDefaultRoom() {
        let activity = [Self.roomB: Self.own(minutes: 20)]
        let recent = Self.updated(activity: activity)
        let later = Self.updated(recent, activity: activity, at: Self.now.addingTimeInterval(15 * 60))
        #expect(recent.newMessageTarget == MergedSendTarget(roomId: Self.roomB, reason: .recentActivity))
        #expect(later.newMessageTarget == MergedSendTarget(roomId: Self.roomA, reason: .defaultRoom))
    }

    @Test func updateReportsWhetherTheTargetChanged() {
        var targeting = MergedComposerTargeting()
        let activity = [Self.roomB: Self.theirs(minutes: 5)]
        let merge = Self.merge
        let firstChange = targeting.update(merge: merge, activity: activity, manualPick: nil, composerHasContent: false, now: Self.now)
        let secondChange = targeting.update(merge: merge, activity: activity, manualPick: nil, composerHasContent: false, now: Self.now)
        #expect(firstChange)
        #expect(!secondChange)
    }

    @Test func mergeWithNoMemberHasNoTarget() {
        var targeting = Self.updated(activity: [:])
        targeting.update(
            merge: MergedChat(id: "empty", name: "Empty", rooms: []),
            activity: [:],
            manualPick: nil,
            composerHasContent: false,
            now: Self.now
        )
        #expect(targeting.newMessageTarget == nil)
    }

    // MARK: - Mode

    @Test func modeWithNothingIsANewMessage() {
        #expect(MergedComposerTargeting.mode(editRoomId: nil, replyRoomId: nil) == .newMessage)
    }

    @Test func modeWithAReplyIsAReply() {
        #expect(MergedComposerTargeting.mode(editRoomId: nil, replyRoomId: Self.roomB) == .reply(eventRoomId: Self.roomB))
    }

    @Test func modeWithAnEditIsAnEdit() {
        #expect(MergedComposerTargeting.mode(editRoomId: Self.roomA, replyRoomId: Self.roomB) == .edit(eventRoomId: Self.roomA))
    }

    /// A reply goes to its event's room for that message only: the memory
    /// keeps the automatic target for the next new message.
    @Test func replyTargetsItsRoomAndKeepsTheAutomaticTarget() {
        let targeting = Self.updated(activity: [Self.roomA: Self.theirs(minutes: 5)])
        let reply = targeting.target(for: .reply(eventRoomId: Self.roomB), rooms: Self.merge.rooms)
        #expect(reply == MergedSendTarget(roomId: Self.roomB, reason: .reply))
        #expect(targeting.target(for: .newMessage, rooms: Self.merge.rooms) == MergedSendTarget(
            roomId: Self.roomA,
            reason: .recentActivity
        ))
    }

    @Test func editTargetsItsRoom() {
        let targeting = Self.updated(activity: [Self.roomA: Self.theirs(minutes: 5)])
        let edit = targeting.target(for: .edit(eventRoomId: Self.roomB), rooms: Self.merge.rooms)
        #expect(edit == MergedSendTarget(roomId: Self.roomB, reason: .edit))
    }

    // MARK: - Typing

    @Test func typingStartsInTheTarget() {
        let notices = MergedChatRouting.composerTypingNotices(previousRoom: nil, currentRoom: Self.roomA, isTyping: true)
        #expect(notices == [.init(roomId: Self.roomA, isTyping: true)])
    }

    @Test func typingRepeatsWhileTheUserKeepsTyping() {
        let notices = MergedChatRouting.composerTypingNotices(previousRoom: Self.roomA, currentRoom: Self.roomA, isTyping: true)
        #expect(notices == [.init(roomId: Self.roomA, isTyping: true)])
    }

    @Test func typingMovesWithTheTarget() {
        let notices = MergedChatRouting.composerTypingNotices(previousRoom: Self.roomA, currentRoom: Self.roomB, isTyping: true)
        #expect(notices == [.init(roomId: Self.roomA, isTyping: false), .init(roomId: Self.roomB, isTyping: true)])
    }

    @Test func clearingTheTextStopsTyping() {
        let notices = MergedChatRouting.composerTypingNotices(previousRoom: Self.roomA, currentRoom: Self.roomA, isTyping: false)
        #expect(notices == [.init(roomId: Self.roomA, isTyping: false)])
    }

    @Test func noTextAndNoTypingRoomSendsNothing() {
        #expect(MergedChatRouting.composerTypingNotices(previousRoom: nil, currentRoom: Self.roomA, isTyping: false).isEmpty)
    }

    @Test func typingRoomFollowsTheNotices() {
        let moved: [MergedChatRouting.TypingNotice] = [
            .init(roomId: Self.roomA, isTyping: false),
            .init(roomId: Self.roomB, isTyping: true),
        ]
        let stopped: [MergedChatRouting.TypingNotice] = [.init(roomId: Self.roomA, isTyping: false)]
        #expect(MergedChatRouting.typingRoom(after: moved, previousRoom: Self.roomA) == Self.roomB)
        #expect(MergedChatRouting.typingRoom(after: stopped, previousRoom: Self.roomA) == nil)
        #expect(MergedChatRouting.typingRoom(after: [], previousRoom: Self.roomA) == Self.roomA)
    }

    // MARK: - Up-arrow edit room

    @Test func newestEditRoomIsTheNewestCandidate() {
        let candidates = [Self.roomA: Self.ago(minutes: 10), Self.roomB: Self.ago(minutes: 2)]
        #expect(MergedComposerTargeting.newestEditRoom(candidates: candidates, rooms: Self.merge.rooms) == Self.roomB)
    }

    @Test func newestEditRoomTieGoesToTheFirstMember() {
        let candidates = [Self.roomA: Self.ago(minutes: 2), Self.roomB: Self.ago(minutes: 2)]
        #expect(MergedComposerTargeting.newestEditRoom(candidates: candidates, rooms: Self.merge.rooms) == Self.roomA)
    }

    @Test func newestEditRoomIgnoresRoomsThatAreNotMembers() {
        let candidates = ["!gone:davlin.io": Self.ago(minutes: 1), Self.roomA: Self.ago(minutes: 30)]
        #expect(MergedComposerTargeting.newestEditRoom(candidates: candidates, rooms: Self.merge.rooms) == Self.roomA)
    }

    @Test func newestEditRoomWithNoCandidateIsNil() {
        #expect(MergedComposerTargeting.newestEditRoom(candidates: [:], rooms: Self.merge.rooms) == nil)
    }
}

/// MATRIX-143 Phase B: the merged composer's in-memory draft rule, and the
/// merged chat's subtitle.
struct MergedComposerDraftsTests {
    @Test func noDraftIsEmpty() {
        #expect(MergedComposerDrafts().text(forMerge: "seth").isEmpty)
    }

    @Test func savesTheComposerText() {
        var drafts = MergedComposerDrafts()
        drafts.save(composerText: "Hi Seth", textBeforeEdit: nil, forMerge: "seth")
        #expect(drafts.text(forMerge: "seth") == "Hi Seth")
        #expect(drafts.text(forMerge: "other").isEmpty)
    }

    @Test func editKeepsTheTextFromBeforeTheEdit() {
        var drafts = MergedComposerDrafts()
        drafts.save(composerText: "the edited message", textBeforeEdit: "my draft", forMerge: "seth")
        #expect(drafts.text(forMerge: "seth") == "my draft")
    }

    @Test func emptyTextRemovesTheDraft() {
        var drafts = MergedComposerDrafts()
        drafts.save(composerText: "Hi", textBeforeEdit: nil, forMerge: "seth")
        drafts.save(composerText: "", textBeforeEdit: nil, forMerge: "seth")
        #expect(drafts == MergedComposerDrafts())
    }

    @Test func removeAllDropsEveryDraft() {
        var drafts = MergedComposerDrafts()
        drafts.save(composerText: "Hi", textBeforeEdit: nil, forMerge: "seth")
        drafts.save(composerText: "Yo", textBeforeEdit: nil, forMerge: "jane")
        drafts.removeAll()
        #expect(drafts == MergedComposerDrafts())
    }

    @Test func subtitleListsTheMemberLabels() {
        let labels = [
            MergedSourceLabel(roomId: "!a:x", network: .slack, roomName: "DevObsessed"),
            MergedSourceLabel(roomId: "!b:x", network: nil, roomName: "pizza box audit committee"),
        ]
        let subtitle = MergedChatHeader.subtitle(labels: labels, failedCount: 0)
        #expect(subtitle.contains("Slack • DevObsessed"))
        #expect(subtitle.contains("pizza box audit committee"))
        #expect(!subtitle.contains("did not load"))
    }

    @Test func subtitleNamesTheRoomsThatDidNotLoad() {
        let labels = [MergedSourceLabel(roomId: "!a:x", network: .slack, roomName: "DevObsessed")]
        #expect(MergedChatHeader.subtitle(labels: labels, failedCount: 1) == "Slack • DevObsessed (1 chat did not load)")
        #expect(MergedChatHeader.subtitle(labels: [], failedCount: 2) == "2 chats did not load")
    }
}

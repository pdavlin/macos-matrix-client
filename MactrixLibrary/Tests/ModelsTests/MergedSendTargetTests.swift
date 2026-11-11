import Foundation
import Models
import Testing

/// MATRIX-143 (M2.5-4): the merged chat's send-target rule (Beeper's rule,
/// contract §11, 2026-11-10).
struct MergedSendTargetTests {
    private static let roomA = "!a:davlin.io"
    private static let roomB = "!b:davlin.io"
    private static let roomC = "!c:davlin.io"
    private static let rooms = [roomA, roomB, roomC]
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func ago(minutes: Double) -> Date {
        now.addingTimeInterval(-minutes * 60)
    }

    /// A room where the other person wrote last, `minutes` ago.
    private static func theirs(minutes: Double) -> MergedSendTarget.RoomActivity {
        .init(newestMessageAt: ago(minutes: minutes))
    }

    /// A room where the account wrote last, `minutes` ago.
    private static func own(minutes: Double) -> MergedSendTarget.RoomActivity {
        .init(newestMessageAt: ago(minutes: minutes), newestOwnMessageAt: ago(minutes: minutes))
    }

    private func resolve(
        rooms: [String] = rooms,
        defaultRoom: String? = roomC,
        _ activity: [String: MergedSendTarget.RoomActivity],
        manualPick: String? = nil
    ) -> MergedSendTarget? {
        MergedSendTarget.resolve(
            rooms: rooms,
            defaultRoom: defaultRoom,
            activity: activity,
            manualPick: manualPick,
            now: Self.now
        )
    }

    // MARK: - Threshold

    @Test func thresholdIsThirtyMinutes() {
        #expect(MergedSendTarget.ownSilenceThreshold == 1800)
    }

    // MARK: - Manual pick

    @Test func manualPickWins() {
        let target = resolve([Self.roomA: Self.theirs(minutes: 1)], manualPick: Self.roomB)
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .chosen))
    }

    @Test func manualPickWinsOverAnOldOwnMessage() {
        let target = resolve([Self.roomA: Self.own(minutes: 300)], manualPick: Self.roomB)
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .chosen))
    }

    @Test func manualPickThatIsNoLongerAMemberIsIgnored() {
        let target = resolve([Self.roomA: Self.theirs(minutes: 1)], manualPick: "!gone:davlin.io")
        #expect(target == MergedSendTarget(roomId: Self.roomA, reason: .recentActivity))
    }

    // MARK: - Newest message by someone else

    /// Seth's case: he wrote in B 5 minutes ago, the account's own last
    /// message is 3 hours old in A. The answer goes to B, not to the default.
    @Test func otherPersonsNewestMessageWinsOverAnOldOwnMessage() {
        let target = resolve(
            defaultRoom: Self.roomA,
            [
                Self.roomA: Self.own(minutes: 180),
                Self.roomB: Self.theirs(minutes: 5),
            ]
        )
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .recentActivity))
    }

    @Test func otherPersonsMessageWinsWithNoOwnMessageAtAll() {
        let target = resolve([Self.roomB: Self.theirs(minutes: 600)])
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .recentActivity))
    }

    @Test func otherPersonsNewestMessageWinsEvenWhenOld() {
        // The default room only takes over after the user's own message.
        let target = resolve([Self.roomA: Self.own(minutes: 900), Self.roomB: Self.theirs(minutes: 600)])
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .recentActivity))
    }

    @Test func otherPersonWroteAfterTheOwnMessageInTheSameRoom() {
        let activity = MergedSendTarget.RoomActivity(
            newestMessageAt: Self.ago(minutes: 2),
            newestOwnMessageAt: Self.ago(minutes: 120)
        )
        let target = resolve([Self.roomB: activity, Self.roomA: Self.theirs(minutes: 30)])
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .recentActivity))
    }

    // MARK: - Newest message is own

    @Test func recentOwnMessageKeepsItsRoom() {
        let target = resolve([Self.roomA: Self.theirs(minutes: 20), Self.roomB: Self.own(minutes: 10)])
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .recentActivity))
    }

    @Test func oldOwnMessageGoesToTheDefaultRoom() {
        let target = resolve([Self.roomA: Self.theirs(minutes: 60), Self.roomB: Self.own(minutes: 31)])
        #expect(target == MergedSendTarget(roomId: Self.roomC, reason: .defaultRoom))
    }

    @Test func ownMessageExactlyAtTheThresholdIsStillRecent() {
        let target = resolve([Self.roomB: Self.own(minutes: 30)])
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .recentActivity))
    }

    @Test func ownMessageJustOverTheThresholdUsesTheDefault() {
        let justOver = MergedSendTarget.RoomActivity(
            newestMessageAt: Self.now.addingTimeInterval(-1801),
            newestOwnMessageAt: Self.now.addingTimeInterval(-1801)
        )
        let target = resolve([Self.roomB: justOver])
        #expect(target == MergedSendTarget(roomId: Self.roomC, reason: .defaultRoom))
    }

    @Test func ownMessageWithAnEmptyNewestTimeStillCounts() {
        let activity = MergedSendTarget.RoomActivity(newestOwnMessageAt: Self.ago(minutes: 5))
        let target = resolve([Self.roomB: activity, Self.roomA: Self.theirs(minutes: 10)])
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .recentActivity))
    }

    @Test func ownMessageNewerThanTheNewestTimeCountsAsNewest() {
        // Inconsistent input: own newer than "newest by anyone". Own wins.
        let activity = MergedSendTarget.RoomActivity(
            newestMessageAt: Self.ago(minutes: 100),
            newestOwnMessageAt: Self.ago(minutes: 40)
        )
        let target = resolve([Self.roomB: activity, Self.roomA: Self.theirs(minutes: 50)])
        #expect(target == MergedSendTarget(roomId: Self.roomC, reason: .defaultRoom))
    }

    @Test func ownMessageInTheFutureIsRecent() {
        // Clock skew between the server and this Mac.
        let target = resolve([Self.roomB: Self.own(minutes: -2)])
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .recentActivity))
    }

    // MARK: - No messages

    @Test func noMessagesUsesTheDefaultRoom() {
        #expect(resolve([:]) == MergedSendTarget(roomId: Self.roomC, reason: .defaultRoom))
    }

    @Test func emptyActivityValuesUseTheDefaultRoom() {
        let target = resolve([Self.roomA: .init(), Self.roomB: .init()])
        #expect(target == MergedSendTarget(roomId: Self.roomC, reason: .defaultRoom))
    }

    @Test func activityOfNonMembersIsIgnored() {
        let target = resolve(["!other:davlin.io": Self.theirs(minutes: 1)])
        #expect(target == MergedSendTarget(roomId: Self.roomC, reason: .defaultRoom))
    }

    // MARK: - Default room

    @Test func missingDefaultRoomFallsBackToTheFirstMember() {
        let target = resolve(defaultRoom: nil, [:])
        #expect(target == MergedSendTarget(roomId: Self.roomA, reason: .defaultRoom))
    }

    @Test func defaultRoomThatIsNoLongerAMemberFallsBackToTheFirstMember() {
        let target = resolve(defaultRoom: "!gone:davlin.io", [Self.roomB: Self.own(minutes: 45)])
        #expect(target == MergedSendTarget(roomId: Self.roomA, reason: .defaultRoom))
    }

    @Test func noMembersGiveNoTarget() {
        #expect(resolve(rooms: [], [:], manualPick: Self.roomA) == nil)
    }

    // MARK: - Ties

    @Test func tieGoesToTheEarlierMember() {
        let target = resolve([Self.roomC: Self.theirs(minutes: 5), Self.roomB: Self.theirs(minutes: 5)])
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .recentActivity))
    }

    @Test func tieFollowsMemberOrderNotDictionaryOrder() {
        let reversed = [Self.roomC, Self.roomB, Self.roomA]
        let activity = [Self.roomA: Self.theirs(minutes: 5), Self.roomC: Self.theirs(minutes: 5)]
        #expect(resolve(rooms: reversed, activity)?.roomId == Self.roomC)
        #expect(resolve(activity)?.roomId == Self.roomA)
    }

    @Test func tieWithAnOldOwnMessageFirstUsesTheDefault() {
        // A own and B theirs at the same time: A comes first, its message is
        // own and old, so the default room takes over.
        let target = resolve(
            defaultRoom: Self.roomC,
            [Self.roomA: Self.own(minutes: 45), Self.roomB: Self.theirs(minutes: 45)]
        )
        #expect(target == MergedSendTarget(roomId: Self.roomC, reason: .defaultRoom))
    }

    // MARK: - Merged chat entry point

    @Test func resolveForMergeUsesItsEffectiveDefaultRoom() {
        let merge = MergedChat(id: "m", name: "Seth", rooms: Self.rooms, defaultRoom: Self.roomB)
        let target = MergedSendTarget.resolve(for: merge, activity: [:], manualPick: nil, now: Self.now)
        #expect(target == MergedSendTarget(roomId: Self.roomB, reason: .defaultRoom))
    }

    @Test func resolveForMergeWithAStaleDefaultUsesTheFirstMember() {
        let merge = MergedChat(id: "m", name: "Seth", rooms: Self.rooms, defaultRoom: "!gone:davlin.io")
        let target = MergedSendTarget.resolve(for: merge, activity: [:], manualPick: nil, now: Self.now)
        #expect(target == MergedSendTarget(roomId: Self.roomA, reason: .defaultRoom))
    }

    // MARK: - Automatic

    @Test func onlyRuleReasonsAreAutomatic() {
        let automatic = MergedSendTarget.Reason.allCases.filter {
            MergedSendTarget(roomId: Self.roomA, reason: $0).isAutomatic
        }
        #expect(Set(automatic) == [.recentActivity, .defaultRoom])
    }

    // MARK: - Stability while writing

    @Test func emptyComposerFollowsNewActivity() {
        let previous = MergedSendTarget(roomId: Self.roomA, reason: .recentActivity)
        let resolved = MergedSendTarget(roomId: Self.roomB, reason: .recentActivity)
        let shown = MergedSendTarget.stabilized(resolved, previous: previous, composerHasContent: false, rooms: Self.rooms)
        #expect(shown == resolved)
    }

    @Test func composerWithContentKeepsTheAutomaticTarget() {
        let previous = MergedSendTarget(roomId: Self.roomA, reason: .recentActivity)
        let resolved = MergedSendTarget(roomId: Self.roomB, reason: .recentActivity)
        let shown = MergedSendTarget.stabilized(resolved, previous: previous, composerHasContent: true, rooms: Self.rooms)
        #expect(shown == previous)
    }

    @Test func manualPickTakesEffectWhileWriting() {
        let previous = MergedSendTarget(roomId: Self.roomA, reason: .recentActivity)
        let resolved = MergedSendTarget(roomId: Self.roomB, reason: .chosen)
        let shown = MergedSendTarget.stabilized(resolved, previous: previous, composerHasContent: true, rooms: Self.rooms)
        #expect(shown == resolved)
    }

    @Test func clearingAManualPickWhileWritingUsesTheRule() {
        let previous = MergedSendTarget(roomId: Self.roomA, reason: .chosen)
        let resolved = MergedSendTarget(roomId: Self.roomB, reason: .defaultRoom)
        let shown = MergedSendTarget.stabilized(resolved, previous: previous, composerHasContent: true, rooms: Self.rooms)
        #expect(shown == resolved)
    }

    @Test func previousTargetThatLeftTheMergeIsDropped() {
        let previous = MergedSendTarget(roomId: "!gone:davlin.io", reason: .recentActivity)
        let resolved = MergedSendTarget(roomId: Self.roomB, reason: .recentActivity)
        let shown = MergedSendTarget.stabilized(resolved, previous: previous, composerHasContent: true, rooms: Self.rooms)
        #expect(shown == resolved)
    }

    @Test func noPreviousTargetUsesTheRule() {
        let resolved = MergedSendTarget(roomId: Self.roomB, reason: .recentActivity)
        let shown = MergedSendTarget.stabilized(resolved, previous: nil, composerHasContent: true, rooms: Self.rooms)
        #expect(shown == resolved)
    }
}

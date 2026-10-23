import Foundation
@testable import Models
import Testing

/// An event with the two fields grouping reads, set per test.
struct GroupingTestEvent: EventTimelineItem {
    var sender: String
    var date: Date
    var isOwn = false

    var isRemote: Bool { true }
    var senderProfileDetails: ProfileDetails { .ready(displayName: nil, displayNameAmbiguous: false, avatarUrl: nil) }
    var isEditable: Bool { false }
    var sendState: LocalSendState? { nil }
    var localCreatedAt: UInt64? { nil }
    var userReadReceipts: [String: Receipt] { [:] }
    var canBeRepliedTo: Bool { true }
    var userId: String { sender }
    var displayName: String? { nil }
    var avatarUrl: String? { nil }
}

/// MATRIX-68: sender grouping and the gap rhythm, as pure logic.
///
/// Every case is stated as Beeper states it — the gap *below* the earlier
/// message — and asserted as the row model stores it, the gap *above* the
/// later one. The pair and the value are the same; only the owner moves.
struct TimelineRowGroupingTests {
    /// A fixed zone, so "the same day" does not depend on the machine.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// 2026-10-23 09:00:00 UTC.
    private static let morning = Date(timeIntervalSince1970: 1_792_746_000)

    private func anchor(_ sender: String, minutes: Double) -> TimelineGroupingAnchor {
        TimelineGroupingAnchor(senderId: sender, date: Self.morning.addingTimeInterval(minutes * 60))
    }

    private func derive(_ row: TimelineGroupingAnchor, after predecessor: TimelineGroupingAnchor?) -> TimelineRowGrouping {
        TimelineRowGrouping.derive(row, after: predecessor, calendar: Self.calendar)
    }

    private func message(_ id: String, _ sender: String, minutes: Double) -> TimelineRow {
        .message(
            uniqueId: id,
            event: GroupingTestEvent(sender: sender, date: Self.morning.addingTimeInterval(minutes * 60)),
            kind: .text,
            heightFingerprint: .stub()
        )
    }

    private func state(_ id: String, minutes: Double) -> TimelineRow {
        .state(
            uniqueId: id,
            event: GroupingTestEvent(sender: "@ada:example.org", date: Self.morning.addingTimeInterval(minutes * 60)),
            name: "joined"
        )
    }

    // MARK: - The bands

    @Test
    func sameSenderWithinAMinuteContinuesTheRunWithTheTightestGap() {
        let grouping = derive(anchor("@ada:example.org", minutes: 1), after: anchor("@ada:example.org", minutes: 0))

        #expect(grouping == TimelineRowGrouping(isContinuation: true, gap: .sameSenderBurst))
        #expect(!grouping.showsProfileHeader)
    }

    @Test
    func otherSenderWithinAMinuteStartsARunWithTheTurnGap() {
        let grouping = derive(anchor("@bob:example.org", minutes: 0.5), after: anchor("@ada:example.org", minutes: 0))

        #expect(grouping == TimelineRowGrouping(isContinuation: false, gap: .senderTurn))
        #expect(grouping.showsProfileHeader)
    }

    @Test
    func moreThanAMinuteIsAShortPauseForEitherSender() {
        let same = derive(anchor("@ada:example.org", minutes: 1.5), after: anchor("@ada:example.org", minutes: 0))
        let other = derive(anchor("@bob:example.org", minutes: 5), after: anchor("@ada:example.org", minutes: 0))

        #expect(same == TimelineRowGrouping(isContinuation: true, gap: .shortPause))
        #expect(other == TimelineRowGrouping(isContinuation: false, gap: .shortPause))
    }

    @Test
    func moreThanFiveMinutesIsAPause() {
        let grouping = derive(anchor("@ada:example.org", minutes: 5.5), after: anchor("@ada:example.org", minutes: 0))

        #expect(grouping == TimelineRowGrouping(isContinuation: true, gap: .pause))
    }

    @Test
    func moreThanFourHoursIsALongPauseAndStillContinuesTheRun() {
        // Beeper breaks a run on sender, day, and non-message rows only. Time
        // alone does not break it; only the gap says how long the pause was.
        let grouping = derive(anchor("@ada:example.org", minutes: 241), after: anchor("@ada:example.org", minutes: 0))

        #expect(grouping == TimelineRowGrouping(isContinuation: true, gap: .longPause))
    }

    @Test
    func bandBoundariesAreStrictlyGreaterThan() {
        let ada = "@ada:example.org"
        #expect(derive(anchor(ada, minutes: 1), after: anchor(ada, minutes: 0)).gap == .sameSenderBurst)
        #expect(derive(anchor(ada, minutes: 5), after: anchor(ada, minutes: 0)).gap == .shortPause)
        #expect(derive(anchor(ada, minutes: 240), after: anchor(ada, minutes: 0)).gap == .pause)
    }

    @Test
    func aClockThatRunsBackwardsIsStillABurst() {
        // A local echo's clock can run ahead of the server's.
        let grouping = derive(anchor("@ada:example.org", minutes: -2), after: anchor("@ada:example.org", minutes: 0))

        #expect(grouping == TimelineRowGrouping(isContinuation: true, gap: .sameSenderBurst))
    }

    // MARK: - Run breaks

    @Test
    func aDayChangeBreaksTheRunWithNoRhythmGap() {
        // 23:59:30 and 00:00:10 the next day: forty seconds, same sender, but a
        // date divider sits between them.
        let lateNight = TimelineGroupingAnchor(
            senderId: "@ada:example.org",
            date: Self.morning.addingTimeInterval(14 * 3600 + 59 * 60 + 30)
        )
        let pastMidnight = TimelineGroupingAnchor(senderId: "@ada:example.org", date: lateNight.date.addingTimeInterval(40))

        #expect(derive(pastMidnight, after: lateNight) == .standalone)
    }

    @Test
    func noMessagePredecessorStartsARunWithTodaysSpacing() {
        #expect(derive(anchor("@ada:example.org", minutes: 0), after: nil) == .standalone)
        #expect(TimelineRowGrouping.standalone == TimelineRowGrouping(isContinuation: false, gap: .none))
    }

    @Test
    func everyNonMessageRowBreaksTheRun() {
        let predecessors: [TimelineRow] = [
            state("s", minutes: 0),
            .virtual(uniqueId: "d", item: .dateDivider(date: Self.morning)),
            .virtual(uniqueId: "r", item: .readMarker),
            .virtual(uniqueId: "t", item: .timelineStart),
            .typingIndicator(uniqueId: "typing", names: ["Ada"]),
            .paginationActivity(uniqueId: "p"),
            .paginationFailure(uniqueId: "f", message: "offline"),
            .unsupported(uniqueId: "x"),
        ]
        let row = message("m", "@ada:example.org", minutes: 0.5)

        for predecessor in predecessors {
            #expect(predecessor.groupingAnchor == nil)
            #expect(row.regrouped(after: predecessor, calendar: Self.calendar).grouping == .standalone)
        }
    }

    @Test
    func nonMessageRowsHaveNoGroupingAndAreNeverRegrouped() {
        let state = state("s", minutes: 1)
        let regrouped = state.regrouped(after: message("m", "@ada:example.org", minutes: 0), calendar: Self.calendar)

        #expect(regrouped.grouping == nil)
        #expect(regrouped.uniqueId == "s")
    }

    // MARK: - Row-array order

    @Test
    func thePredecessorOfARowIsTheNextIndexInNewestFirstOrder() {
        #expect(TimelineRowRegrouping.predecessorIndex(of: 3) == 4)
        #expect(TimelineRowRegrouping.successorIndex(of: 3) == 2)
    }

    @Test
    func regroupAllGroupsANewestFirstArrayAgainstChronologicalPredecessors() {
        // Newest first, the way the container holds rows.
        var rows: [TimelineRow] = [
            message("m4", "@bob:example.org", minutes: 300),
            message("m3", "@ada:example.org", minutes: 2),
            message("m2", "@ada:example.org", minutes: 0.5),
            message("m1", "@ada:example.org", minutes: 0),
            state("s0", minutes: -1),
        ]

        TimelineRowRegrouping.regroupAll(&rows, calendar: Self.calendar)

        #expect(rows.map(\.grouping) == [
            TimelineRowGrouping(isContinuation: false, gap: .longPause),
            TimelineRowGrouping(isContinuation: true, gap: .shortPause),
            TimelineRowGrouping(isContinuation: true, gap: .sameSenderBurst),
            .standalone,
            nil,
        ])
    }

    @Test
    func regroupRowReportsWhetherTheGroupingChanged() {
        var rows: [TimelineRow] = [
            message("m2", "@ada:example.org", minutes: 0.5),
            message("m1", "@ada:example.org", minutes: 0),
        ]

        #expect(TimelineRowRegrouping.regroupRow(at: 0, in: &rows, calendar: Self.calendar))
        #expect(!TimelineRowRegrouping.regroupRow(at: 0, in: &rows, calendar: Self.calendar))
        #expect(!TimelineRowRegrouping.regroupRow(at: 5, in: &rows, calendar: Self.calendar))
        #expect(!TimelineRowRegrouping.regroupRow(at: -1, in: &rows, calendar: Self.calendar))
    }

    @Test
    func aMessageArrivingAtTheNewestEndNeverRegroupsTheRowBeforeIt() {
        // The reason grouping reads the predecessor: the older row's grouping
        // is a function of *its* predecessor, which the arrival did not touch.
        var rows: [TimelineRow] = [
            message("m2", "@ada:example.org", minutes: 0.5),
            message("m1", "@bob:example.org", minutes: 0),
        ]
        TimelineRowRegrouping.regroupAll(&rows, calendar: Self.calendar)
        let before = rows[0].grouping

        rows.insert(message("m3", "@ada:example.org", minutes: 0.7), at: 0)
        TimelineRowRegrouping.regroupRow(at: 0, in: &rows, calendar: Self.calendar)

        #expect(!TimelineRowRegrouping.regroupRow(at: 1, in: &rows, calendar: Self.calendar))
        #expect(rows[1].grouping == before)
        #expect(rows[0].grouping == TimelineRowGrouping(isContinuation: true, gap: .sameSenderBurst))
    }

    @Test
    func aBackPaginationPrependRegroupsTheOldestPreviouslyLoadedRow() {
        var rows: [TimelineRow] = [
            message("m2", "@ada:example.org", minutes: 1),
        ]
        TimelineRowRegrouping.regroupAll(&rows, calendar: Self.calendar)
        #expect(rows[0].grouping == .standalone)

        // An older message from the same sender lands at the oldest end, which
        // is the end of a newest-first array.
        rows.append(message("m1", "@ada:example.org", minutes: 0.5))
        TimelineRowRegrouping.regroupRow(at: 1, in: &rows, calendar: Self.calendar)

        #expect(TimelineRowRegrouping.regroupRow(at: 0, in: &rows, calendar: Self.calendar))
        #expect(rows[0].grouping == TimelineRowGrouping(isContinuation: true, gap: .sameSenderBurst))
    }

    // MARK: - Reuse pools

    @Test
    func continuationRowsRecycleFromTheirOwnPool() {
        let lead = message("m1", "@ada:example.org", minutes: 0)
        let continuation = message("m2", "@ada:example.org", minutes: 0.5).regrouped(after: lead, calendar: Self.calendar)

        #expect(lead.reuseId == "message.text")
        #expect(continuation.reuseId == "message.text.continuation")
    }

    @Test
    func theGapBandDoesNotSplitThePool() {
        let lead = message("m1", "@ada:example.org", minutes: 0)
        let burst = message("m2", "@ada:example.org", minutes: 0.5).regrouped(after: lead, calendar: Self.calendar)
        let pause = message("m3", "@ada:example.org", minutes: 30).regrouped(after: lead, calendar: Self.calendar)

        #expect(burst.grouping?.gap != pause.grouping?.gap)
        #expect(burst.reuseId == pause.reuseId)
    }
}

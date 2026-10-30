import Foundation
@testable import Models
import Testing

/// MATRIX-85: sender runs for the iOS row container, with the
/// `TimelineGroups` rule.
struct TimelineSenderGroupingTests {
    private struct Event: EventTimelineItem {
        let sender: String
        var isRemote: Bool { true }
        var senderProfileDetails: ProfileDetails { .unavailable }
        var isOwn: Bool { false }
        var isEditable: Bool { false }
        var date: Date { Date(timeIntervalSince1970: 0) }
        var sendState: LocalSendState? { nil }
        var localCreatedAt: UInt64? { nil }
        var userReadReceipts: [String: Receipt] { [:] }
        var canBeRepliedTo: Bool { true }
        var userId: String { sender }
        var displayName: String? { nil }
        var avatarUrl: String? { nil }
    }

    private func message(_ id: String, from sender: String) -> TimelineRow {
        .message(uniqueId: id, event: Event(sender: sender), kind: .text, heightFingerprint: .stub())
    }

    @Test
    func oldestMessageOpensARun() {
        #expect(TimelineSenderGrouping.showsSenderHeader(message("a", from: "@ada"), olderNeighbor: nil))
    }

    @Test
    func sameSenderContinuesTheRun() {
        let older = message("a", from: "@ada")
        let newer = message("b", from: "@ada")

        #expect(!TimelineSenderGrouping.showsSenderHeader(newer, olderNeighbor: older))
    }

    @Test
    func otherSenderOpensARun() {
        let older = message("a", from: "@ada")
        let newer = message("b", from: "@bob")

        #expect(TimelineSenderGrouping.showsSenderHeader(newer, olderNeighbor: older))
    }

    @Test
    func dayDividerBetweenSameSenderOpensARun() {
        let divider = TimelineRow.virtual(uniqueId: "d", item: .dateDivider(date: .now))

        #expect(TimelineSenderGrouping.showsSenderHeader(message("b", from: "@ada"), olderNeighbor: divider))
    }

    @Test
    func readMarkerBetweenSameSenderOpensARun() {
        let marker = TimelineRow.virtual(uniqueId: "r", item: .readMarker)

        #expect(TimelineSenderGrouping.showsSenderHeader(message("b", from: "@ada"), olderNeighbor: marker))
    }

    @Test
    func nonMessageRowsNeverDrawAHeader() {
        let divider = TimelineRow.virtual(uniqueId: "d", item: .dateDivider(date: .now))
        let typing = TimelineRow.typingIndicator(uniqueId: "t", names: ["Ada"])

        #expect(!TimelineSenderGrouping.showsSenderHeader(divider, olderNeighbor: nil))
        #expect(!TimelineSenderGrouping.showsSenderHeader(typing, olderNeighbor: message("a", from: "@ada")))
    }

    @Test
    func insertRegroupsTheInsertedRowsAndTheNewerNeighbor() {
        let rows = TimelineSenderGrouping.rowsToRegroup(after: .insert(index: 3, count: 2), rowCount: 10)

        #expect(rows == 2 ..< 5)
    }

    @Test
    func insertAtTheNewestEndHasNoNewerNeighbor() {
        let rows = TimelineSenderGrouping.rowsToRegroup(after: .insert(index: 0, count: 1), rowCount: 10)

        #expect(rows == 0 ..< 1)
    }

    @Test
    func backPaginationRegroupsTheFormerOldestRow() {
        // 8 rows, 4 older ones appended at the oldest end: row 7 gains an older
        // neighbor and can lose its header.
        let rows = TimelineSenderGrouping.rowsToRegroup(after: .insert(index: 8, count: 4), rowCount: 12)

        #expect(rows == 7 ..< 12)
    }

    @Test
    func removeRegroupsOnlyTheNewerNeighbor() {
        let rows = TimelineSenderGrouping.rowsToRegroup(after: .remove(index: 4, count: 3), rowCount: 7)

        #expect(rows == 3 ..< 4)
    }

    @Test
    func removeAtTheNewestEndRegroupsNothing() {
        let rows = TimelineSenderGrouping.rowsToRegroup(after: .remove(index: 0, count: 1), rowCount: 7)

        #expect(rows.isEmpty)
    }

    @Test
    func updateRegroupsTheRowAndItsNewerNeighbor() {
        let rows = TimelineSenderGrouping.rowsToRegroup(after: .update(index: 5), rowCount: 9)

        #expect(rows == 4 ..< 6)
    }

    @Test
    func resetRegroupsEverything() {
        let rows = TimelineSenderGrouping.rowsToRegroup(after: .reset, rowCount: 9)

        #expect(rows == 0 ..< 9)
    }

    @Test
    func rangesClampToTheRowCount() {
        // A stale index past the end must not produce an out-of-bounds range.
        let rows = TimelineSenderGrouping.rowsToRegroup(after: .update(index: 20), rowCount: 9)

        #expect(rows.isEmpty)
    }
}

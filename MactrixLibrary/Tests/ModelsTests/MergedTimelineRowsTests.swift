import Foundation
@testable import Models
import Testing

/// MATRIX-142 Phase B: the rows the merged timeline publishes, built from the
/// merge engine's entries.
struct MergedTimelineRowsTests: MergedTimelineRowFixtures {
    // MARK: - Orientation and identity

    @Test
    func rowsAreNewestFirstWithTheMergedIdentifiers() {
        let rows = displayRows([
            rowMember(
                roomA,
                [message("a1", in: roomA, from: bob, minutes: 0), message("a2", in: roomA, from: bob, minutes: 2)],
                reachedStart: true
            ),
            rowMember(roomB, [message("b1", in: roomB, from: bob, minutes: 1)], reachedStart: true),
        ])

        #expect(render(rows) == ["a2", "note:!a", "b1", "note:!b", "a1", "note:!a", "day", "start"])
        #expect(rows[0].id == MergedTimelineEntryID.item(roomId: roomA, itemId: "a2"))
        #expect(rows[0].row.uniqueId == rows[0].id)
        #expect(rows[6].id == MergedTimelineEntryID.day(of: morning, calendar: calendar))
        #expect(rows[7].id == MergedTimelineEntryID.timelineStart)
    }

    @Test
    func rowsMatchTheEntriesInReverse() {
        let members = [
            rowMember(roomA, [
                message("a1", in: roomA, from: bob, minutes: 0),
                sdkReadMarker(),
                message("a2", in: roomA, from: bob, minutes: 3),
            ]),
            rowMember(roomB, [message("b1", in: roomB, from: ada, minutes: 1)], reachedStart: true),
        ]
        let content = MergedTimelineMerger.merge(members, calendar: calendar)
        let rows = MergedTimelineRowBuilder.displayRows(from: content, labels: [:], calendar: calendar)

        #expect(rows.map(\.id) == content.newestFirst.map(\.id))
    }

    @Test
    func anItemRowWithItsOwnIdentifierGetsTheMergedOne() {
        let item = RowTestItem(
            mergedItemId: "7",
            mergedItemKind: .event(serverTimestamp: morning),
            mergedRow: .message(
                uniqueId: "7",
                event: GroupingTestEvent(sender: bob, date: morning),
                kind: .text,
                heightFingerprint: .stub()
            ),
            mergedContentRevision: 0,
            mergedReceiptEventId: "$7"
        )
        let rows = displayRows([rowMember(roomA, [item])])

        #expect(rows.first?.row.uniqueId == MergedTimelineEntryID.item(roomId: roomA, itemId: "7"))
    }

    @Test
    func theMergedVirtualEntriesBecomeVirtualRows() {
        let rows = displayRows([
            rowMember(
                roomA,
                [message("a1", in: roomA, from: bob, minutes: 0), sdkReadMarker(), message("a2", in: roomA, from: bob, minutes: 1)],
                reachedStart: true
            ),
        ])

        #expect(render(rows) == ["a2", "read", "a1", "day", "start"])
        guard case .virtual(_, .readMarker) = rows[1].row,
              case let .virtual(_, .dateDivider(date)) = rows[3].row,
              case .virtual(_, .timelineStart) = rows[4].row
        else {
            Issue.record("expected the read marker, a day divider, and the timeline start")
            return
        }
        #expect(date == calendar.startOfDay(for: morning))
        #expect(rows[1].roomId == nil)
        #expect(rows[1].receiptEventId == nil)
    }

    @Test
    func itemRowsCarryTheirRoomTimeAndReceiptEvent() {
        let rows = displayRows([
            rowMember(roomA, [message("a1", in: roomA, from: bob, minutes: 0, revision: 4), localEcho("e1", in: roomA, minutes: 5)]),
        ])

        #expect(render(rows) == ["e1", "a1", "day"])
        #expect(rows[1].roomId == roomA)
        #expect(rows[1].receiptEventId == "$a1")
        #expect(rows[1].serverTimestamp == morning)
        #expect(rows[1].contentRevision == 4)
        // A local echo is not on the server: no time to compare, no receipt.
        #expect(rows[0].serverTimestamp == nil)
        #expect(rows[0].receiptEventId == nil)
    }

    // MARK: - Source notes

    @Test
    func aSourceNoteCarriesItsRoomsLabel() throws {
        let label = MergedSourceLabel(roomId: roomB, network: .slack, roomName: "Seth")
        let rows = displayRows(
            [
                rowMember(roomA, [message("a1", in: roomA, from: bob, minutes: 0)], reachedStart: true),
                rowMember(roomB, [message("b1", in: roomB, from: bob, minutes: 1)], reachedStart: true),
            ],
            labels: [roomB: label]
        )

        let note = try #require(rows.first { $0.sourceLabel?.roomId == roomB })
        #expect(note.sourceLabel == label)
        #expect(note.roomId == roomB)
        #expect(note.receiptEventId == nil)
        #expect(note.row.reuseId == "virtual.mergedSource")
        #expect(note.row.fixedHeight == MergedSourceLabel.rowHeight)
        #expect(note.row.heightFingerprint == nil)
        #expect(note.row.isDecoration == false)
    }

    @Test
    func aRoomWithoutALabelShowsItsRoomId() throws {
        let rows = displayRows([
            rowMember(roomA, [message("a1", in: roomA, from: bob, minutes: 0)], reachedStart: true),
            rowMember(roomB, [message("b1", in: roomB, from: bob, minutes: 1)], reachedStart: true),
        ])

        let note = try #require(rows.first { $0.sourceLabel?.roomId == roomB })
        #expect(note.sourceLabel == MergedSourceLabel(roomId: roomB, network: nil, title: roomB, detail: nil))
    }

    @Test
    func theLabelRuleNamesTheNetworkThenTheRoom() {
        #expect(
            MergedSourceLabel(roomId: roomA, network: .slack, roomName: "Seth")
                == MergedSourceLabel(roomId: roomA, network: .slack, title: "Slack", detail: "Seth")
        )
        #expect(
            MergedSourceLabel(roomId: roomA, network: .googleChat, roomName: nil)
                == MergedSourceLabel(roomId: roomA, network: .googleChat, title: "Google Chat", detail: nil)
        )
        #expect(
            MergedSourceLabel(roomId: roomA, network: nil, roomName: "  Seth ")
                == MergedSourceLabel(roomId: roomA, network: nil, title: "Seth", detail: nil)
        )
        #expect(
            MergedSourceLabel(roomId: roomA, network: nil, roomName: "   ")
                == MergedSourceLabel(roomId: roomA, network: nil, title: roomA, detail: nil)
        )
    }

    // MARK: - Sender grouping

    @Test
    func aSenderRunBreaksWhereTheRoomChanges() {
        // The same sender writes in room A, then in room B, within a minute.
        let rows = displayRows([
            rowMember(
                roomA,
                [message("a1", in: roomA, from: ada, minutes: 0), message("a2", in: roomA, from: ada, minutes: 0.2)],
                reachedStart: true
            ),
            rowMember(
                roomB,
                [message("b1", in: roomB, from: ada, minutes: 0.4), message("b2", in: roomB, from: ada, minutes: 0.6)],
                reachedStart: true
            ),
        ])

        #expect(render(rows) == ["b2", "b1", "note:!b", "a2", "a1", "note:!a", "day", "start"])
        #expect(showsHeader(rows[0]) == false)
        #expect(showsHeader(rows[1]) == true)
        #expect(showsHeader(rows[3]) == false)
        #expect(showsHeader(rows[4]) == true)
    }

    @Test
    func aRunInsideOneRoomGroupsAsInASingleRoom() {
        let rows = displayRows([
            rowMember(roomA, [
                message("a1", in: roomA, from: bob, minutes: 0),
                message("a2", in: roomA, from: bob, minutes: 0.5),
                message("a3", in: roomA, from: ada, minutes: 0.7),
            ]),
        ])

        #expect(render(rows) == ["a3", "a2", "a1", "day"])
        #expect(rows[0].row.grouping == TimelineRowGrouping(isContinuation: false, gap: .senderTurn))
        #expect(rows[1].row.grouping == TimelineRowGrouping(isContinuation: true, gap: .sameSenderBurst))
        #expect(rows[2].row.grouping == .standalone)
    }

    @Test
    func theBuiltGroupingIsWhatTheContainerWouldDerive() {
        let rows = displayRows([
            rowMember(roomA, [
                message("a1", in: roomA, from: ada, minutes: 0),
                message("a2", in: roomA, from: bob, minutes: 0.3),
                message("a3", in: roomA, from: bob, minutes: 9),
            ]),
            rowMember(roomB, [message("b1", in: roomB, from: bob, minutes: 0.5), message("b2", in: roomB, from: bob, minutes: 0.6)]),
        ])
        var regrouped = rows.map(\.row)
        TimelineRowRegrouping.regroupAll(&regrouped, calendar: calendar)

        #expect(regrouped.map(\.grouping) == rows.map(\.row.grouping))
    }

    // MARK: - Content comparison

    @Test
    func contentChangesWithTheRevisionTheGroupingOrTheLabel() {
        let base = displayRows([rowMember(roomA, [message("a1", in: roomA, from: bob, minutes: 0)])])[0]
        let sameRevision = displayRows([rowMember(roomA, [message("a1", in: roomA, from: bob, minutes: 0)])])[0]
        let newRevision = displayRows([rowMember(roomA, [message("a1", in: roomA, from: bob, minutes: 0, revision: 1)])])[0]
        let regrouped = MergedDisplayRow(
            row: base.row.regrouped(after: message("a0", in: roomA, from: bob, minutes: -0.5).mergedRow, calendar: calendar),
            roomId: base.roomId,
            receiptEventId: base.receiptEventId,
            serverTimestamp: base.serverTimestamp,
            contentRevision: base.contentRevision
        )
        let labelA = MergedSourceLabel(roomId: roomA, network: nil, roomName: "A")
        let labelB = MergedSourceLabel(roomId: roomA, network: nil, roomName: "B")
        let note = MergedDisplayRow(row: .virtual(uniqueId: "n", item: .mergedSource(labelA)))
        let renamed = MergedDisplayRow(row: .virtual(uniqueId: "n", item: .mergedSource(labelB)))

        #expect(base.hasSameContent(as: sameRevision))
        #expect(!base.hasSameContent(as: newRevision))
        #expect(!base.hasSameContent(as: regrouped))
        #expect(note.hasSameContent(as: note))
        #expect(!note.hasSameContent(as: renamed))
    }
}

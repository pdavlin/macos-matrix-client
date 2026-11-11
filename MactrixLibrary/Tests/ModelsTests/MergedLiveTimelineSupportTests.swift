import Foundation
@testable import Models
import Testing

/// MATRIX-142 Phase B: read receipt mapping, send-target activity, and the
/// recompute coalescing of the merged live timeline.
struct MergedLiveTimelineSupportTests: MergedTimelineRowFixtures {
    // MARK: - Read receipts

    /// Newest first: a3, b2 (echo), b1, note, a2, a1, … across two rooms.
    private func receiptRows() -> [MergedDisplayRow] {
        displayRows([
            rowMember(roomA, [
                message("a1", in: roomA, from: bob, minutes: 0),
                message("a2", in: roomA, from: bob, minutes: 1),
                message("a3", in: roomA, from: bob, minutes: 4),
            ], reachedStart: true),
            rowMember(roomB, [
                message("b1", in: roomB, from: bob, minutes: 2),
                localEcho("b2", in: roomB, minutes: 3),
            ], reachedStart: true),
        ])
    }

    @Test
    func eachRoomGetsItsNewestEventAtOrBelowTheNewestVisibleRow() {
        let rows = receiptRows()
        #expect(render(rows) == ["b2", "note:!b", "a3", "note:!a", "b1", "note:!b", "a2", "a1", "note:!a", "day", "start"])

        let atBottom = MergedReadReceiptMapping.newestVisibleEvents(in: rows, newestVisibleIndex: 0, rooms: [roomA, roomB])
        // The local echo b2 has no event ID yet: room B's newest is b1.
        #expect(atBottom == [
            roomA: MergedReceiptCandidate(eventId: "$a3", serverTimestamp: date(minutes: 4)),
            roomB: MergedReceiptCandidate(eventId: "$b1", serverTimestamp: date(minutes: 2)),
        ])

        let scrolledUp = MergedReadReceiptMapping.newestVisibleEvents(in: rows, newestVisibleIndex: 5, rooms: [roomA, roomB])
        #expect(scrolledUp == [roomA: MergedReceiptCandidate(eventId: "$a2", serverTimestamp: date(minutes: 1))])
    }

    @Test
    func receiptMappingIgnoresRoomsThatAreNotAskedForAndBadIndices() {
        let rows = receiptRows()

        #expect(MergedReadReceiptMapping.newestVisibleEvents(in: rows, newestVisibleIndex: 0, rooms: [roomB]).keys.sorted() == [roomB])
        #expect(MergedReadReceiptMapping.newestVisibleEvents(in: rows, newestVisibleIndex: -3, rooms: [roomA])[roomA]?.eventId == "$a3")
        #expect(MergedReadReceiptMapping.newestVisibleEvents(in: rows, newestVisibleIndex: rows.count, rooms: [roomA]).isEmpty)
        #expect(MergedReadReceiptMapping.newestVisibleEvents(in: [], newestVisibleIndex: 0, rooms: [roomA]).isEmpty)
    }

    @Test
    func onlyReceiptsThatMoveForwardAreSent() {
        let lastSent = [
            roomA: MergedReceiptCandidate(eventId: "$a2", serverTimestamp: date(minutes: 1)),
            roomB: MergedReceiptCandidate(eventId: "$b1", serverTimestamp: date(minutes: 2)),
            roomC: MergedReceiptCandidate(eventId: "$c9", serverTimestamp: date(minutes: 9)),
        ]
        let candidates = [
            roomA: MergedReceiptCandidate(eventId: "$a3", serverTimestamp: date(minutes: 4)),
            roomB: MergedReceiptCandidate(eventId: "$b1", serverTimestamp: date(minutes: 2)),
            roomC: MergedReceiptCandidate(eventId: "$c1", serverTimestamp: date(minutes: 1)),
            "!d": MergedReceiptCandidate(eventId: "$d1", serverTimestamp: date(minutes: 0)),
        ]

        #expect(MergedReadReceiptMapping.advancing(candidates, past: lastSent) == [roomA: "$a3", "!d": "$d1"])
    }

    @Test
    func theMappedEventsRouteThroughTheMergedChatRouting() {
        let rows = receiptRows()
        let candidates = MergedReadReceiptMapping.newestVisibleEvents(in: rows, newestVisibleIndex: 0, rooms: [roomA, roomB])
        let lastSent = [roomB: MergedReceiptCandidate(eventId: "$b1", serverTimestamp: date(minutes: 2))]
        let receipts = MergedChatRouting.readReceipts(
            newestVisibleEvents: MergedReadReceiptMapping.advancing(candidates, past: lastSent),
            alreadySent: lastSent.mapValues(\.eventId),
            rooms: [roomA, roomB]
        )

        #expect(receipts == [MergedChatRouting.ReadReceipt(roomId: roomA, eventId: "$a3")])
    }

    // MARK: - Send-target activity

    @Test
    func activityFindsTheNewestMessageByAnyoneAndBySelf() {
        let activity = MergedSendTarget.RoomActivity(newestFirst: [
            nil,
            MergedMessageActivity(isOwn: false, date: date(minutes: 9)),
            nil,
            MergedMessageActivity(isOwn: true, date: date(minutes: 5)),
            MergedMessageActivity(isOwn: true, date: date(minutes: 1)),
        ])

        #expect(activity == MergedSendTarget.RoomActivity(newestMessageAt: date(minutes: 9), newestOwnMessageAt: date(minutes: 5)))
    }

    @Test
    func activityOfARoomWithoutMessagesOrOwnMessages() {
        #expect(MergedSendTarget.RoomActivity(newestFirst: [nil, nil] as [MergedMessageActivity?]) == MergedSendTarget.RoomActivity())
        #expect(
            MergedSendTarget.RoomActivity(newestFirst: [MergedMessageActivity(isOwn: false, date: date(minutes: 3))])
                == MergedSendTarget.RoomActivity(newestMessageAt: date(minutes: 3), newestOwnMessageAt: nil)
        )
        #expect(
            MergedSendTarget.RoomActivity(newestFirst: [MergedMessageActivity(isOwn: true, date: date(minutes: 3))])
                == MergedSendTarget.RoomActivity(newestMessageAt: date(minutes: 3), newestOwnMessageAt: date(minutes: 3))
        )
    }

    @Test
    func activityStopsReadingOnceBothTimesAreKnown() {
        var read = 0
        let activities = (0 ..< 1000).lazy.map { index -> MergedMessageActivity? in
            read += 1
            return MergedMessageActivity(isOwn: index == 2, date: date(minutes: Double(-index)))
        }
        let activity = MergedSendTarget.RoomActivity(newestFirst: activities)

        #expect(activity.newestOwnMessageAt == date(minutes: -2))
        #expect(read == 3)
    }

    @Test
    func theActivityFeedsTheSendTargetRule() {
        // Room B holds the newest message, from the other person.
        let activity = [
            roomA: MergedSendTarget.RoomActivity(newestFirst: [MergedMessageActivity(isOwn: true, date: date(minutes: 1))]),
            roomB: MergedSendTarget.RoomActivity(newestFirst: [MergedMessageActivity(isOwn: false, date: date(minutes: 2))]),
        ]
        let target = MergedSendTarget.resolve(
            rooms: [roomA, roomB],
            defaultRoom: roomA,
            activity: activity,
            manualPick: nil,
            now: date(minutes: 3)
        )

        #expect(target == MergedSendTarget(roomId: roomB, reason: .recentActivity))
    }

    // MARK: - Coalescing

    @Test
    func onlyTheFirstChangeBeforeAFlushSchedulesIt() {
        var coalescer = MergedRecomputeCoalescer()
        let first = coalescer.markDirty(roomA)
        let second = coalescer.markDirty(roomB)
        let again = coalescer.markDirty(roomA)

        #expect(first)
        #expect(!second)
        #expect(!again)
        #expect(coalescer.isFlushScheduled)
        #expect(coalescer.dirtyRoomIds == [roomA, roomB])
    }

    @Test
    func aFlushTakesTheChangedRoomsAndReArms() {
        var coalescer = MergedRecomputeCoalescer()
        _ = coalescer.markDirty(roomA)
        _ = coalescer.markDirty(roomB)

        let flushed = coalescer.beginFlush()
        #expect(flushed == [roomA, roomB])
        #expect(!coalescer.isFlushScheduled)
        #expect(coalescer.dirtyRoomIds.isEmpty)
        // A change during or after the flush schedules the next one.
        let next = coalescer.markDirty(roomC)
        let nextFlush = coalescer.beginFlush()
        let emptyFlush = coalescer.beginFlush()
        #expect(next)
        #expect(nextFlush == [roomC])
        #expect(emptyFlush.isEmpty)
    }
}

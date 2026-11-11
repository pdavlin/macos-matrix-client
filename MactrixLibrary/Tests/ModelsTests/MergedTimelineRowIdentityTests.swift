import Foundation
@testable import Models
import Testing

/// MATRIX-142 Phase B: the merged row identifiers, the row helpers, the
/// source note's fixed height, and the cached day rule of the row builder.
struct MergedTimelineRowIdentityTests: MergedTimelineRowFixtures {
    // MARK: - Row identifiers

    @Test
    func theRoomOfARowIsFoundAmongTheMembers() {
        let rooms = ["!a:x", "!a:xy", "!b:x"]

        #expect(MergedTimelineEntryID.roomId(ofRowId: MergedTimelineEntryID.item(roomId: "!a:xy", itemId: "3"), among: rooms) == "!a:xy")
        #expect(MergedTimelineEntryID.roomId(ofRowId: MergedTimelineEntryID.item(roomId: "!a:x", itemId: "3"), among: rooms) == "!a:x")
        let note = MergedTimelineEntryID.sourceChange(roomId: "!b:x", firstItemId: "9")
        #expect(MergedTimelineEntryID.roomId(ofRowId: note, among: rooms) == "!b:x")
        #expect(MergedTimelineEntryID.roomId(ofRowId: MergedTimelineEntryID.readMarker, among: rooms) == nil)
        #expect(MergedTimelineEntryID.roomId(ofRowId: MergedTimelineEntryID.timelineStart, among: rooms) == nil)
        #expect(MergedTimelineEntryID.roomId(ofRowId: MergedTimelineEntryID.day(of: morning, calendar: calendar), among: rooms) == nil)
        #expect(MergedTimelineEntryID.roomId(ofRowId: MergedTimelineEntryID.item(roomId: "!c:x", itemId: "3"), among: rooms) == nil)
        #expect(MergedTimelineEntryID.roomId(ofRowId: "7", among: rooms) == nil)
    }

    @Test
    func theItemIdentifierOfARowIsTheSDKOne() {
        let rowId = MergedTimelineEntryID.item(roomId: "!a:x", itemId: "42")

        #expect(MergedTimelineEntryID.itemId(ofRowId: rowId, inRoom: "!a:x") == "42")
        #expect(MergedTimelineEntryID.itemId(ofRowId: rowId, inRoom: "!b:x") == nil)
        let note = MergedTimelineEntryID.sourceChange(roomId: "!a:x", firstItemId: "42")
        #expect(MergedTimelineEntryID.itemId(ofRowId: note, inRoom: "!a:x") == nil)
    }

    @Test
    func withUniqueIdKeepsEveryCaseAndItsContent() {
        let event = GroupingTestEvent(sender: bob, date: morning)
        let rows: [TimelineRow] = [
            .message(uniqueId: "1", event: event, kind: .media, heightFingerprint: .stub()),
            .state(uniqueId: "1", event: event, name: "joined"),
            .virtual(uniqueId: "1", item: .readMarker),
            .typingIndicator(uniqueId: "1", names: ["Bob"]),
            .paginationActivity(uniqueId: "1"),
            .paginationFailure(uniqueId: "1", message: "offline"),
            .unsupported(uniqueId: "1"),
        ]

        for row in rows {
            let renamed = row.withUniqueId("2")
            #expect(renamed.uniqueId == "2")
            #expect(renamed.reuseId == row.reuseId)
            #expect(renamed.heightFingerprint == row.heightFingerprint)
        }
    }

    // MARK: - Fixed height

    @Test
    func onlyTheSourceNoteHasAFixedHeightAndItIsNotMeasured() {
        let note = TimelineRow.virtual(uniqueId: "n", item: .mergedSource(MergedSourceLabel(roomId: roomA, network: nil, roomName: "A")))
        var measured = 0
        let height = TimelineRowMeasurement.height(of: note, width: 300) { _, _ in
            measured += 1
            return 99
        }

        #expect(height == MergedSourceLabel.rowHeight)
        #expect(measured == 0)
        #expect(TimelineRow.virtual(uniqueId: "d", item: .readMarker).fixedHeight == nil)
        #expect(message("a1", in: roomA, from: bob, minutes: 0).mergedRow.fixedHeight == nil)
    }

    // MARK: - Day cache

    /// The cached day rule answers as the calendar does, across daylight
    /// saving changes, in time order and out of it.
    @Test(arguments: ["UTC", "America/New_York", "America/Sao_Paulo", "Australia/Lord_Howe", "Asia/Kolkata"])
    func theDayCacheAgreesWithTheCalendar(zone: String) {
        let calendar = zonedCalendar(zone)
        var cache = TimelineDayCache(calendar: calendar)
        var generator = SplitMix64(seed: UInt64(zone.count))
        // From 2018-11-01, before a São Paulo midnight DST change, for about
        // 250 days in steps of up to four hours, some of them backward.
        var date = Date(timeIntervalSince1970: 1_541_030_400)
        var previous = date
        for _ in 0 ..< 4000 {
            let step = Double(Int.random(in: -3600 ... 14400, using: &generator))
            date = date.addingTimeInterval(step)
            #expect(cache.isSameDay(date, previous) == calendar.isDate(date, inSameDayAs: previous))
            previous = date
        }
    }
}

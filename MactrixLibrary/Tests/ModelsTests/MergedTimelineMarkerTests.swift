import Foundation
@testable import Models
import Testing

/// MATRIX-142: the merged read marker and the source notes.
struct MergedTimelineMarkerTests: MergedTimelineFixtures {
    // MARK: Read marker

    @Test func readMarkerGoesAboveTheFirstUnreadItem() {
        let content = merge([
            member(roomA, [event("a1", minutes: 0), readMarker(), event("a3", minutes: 20)], reachedStart: true),
            member(roomB, [event("b1", minutes: 10), readMarker(), event("b2", minutes: 30)], reachedStart: true),
        ])
        #expect(render(content) == [
            "start", "day:2026-11-10",
            "note:!a", "a1", "note:!b", "b1", "read", "note:!a", "a3", "note:!b", "b2",
        ])
    }

    /// The marker sits above the first unread item; a room whose read
    /// position is newer can still show read items below it.
    @Test func readItemsOfAnotherRoomCanShowBelowTheReadMarker() {
        let content = merge([
            member(roomA, [event("a1", minutes: 0), readMarker(), event("a2", minutes: 10)], reachedStart: true),
            member(roomB, [event("b1", minutes: 20), readMarker(), event("b2", minutes: 30)], reachedStart: true),
        ])
        #expect(items(content) == ["a1", "a2", "b1", "b2"])
        #expect(Array(render(content).drop { $0 != "read" }.prefix(3)) == ["read", "a2", "note:!b"])
    }

    @Test func noReadMarkerWhenNoMemberHasOne() {
        let content = merge([
            member(roomA, [event("a1", minutes: 0)], reachedStart: true),
            member(roomB, [event("b1", minutes: 5)], reachedStart: true),
        ])
        #expect(!render(content).contains("read"))
    }

    /// The read position is not loaded, so the SDK shows no marker either.
    @Test func noReadMarkerWhenTheFirstShownItemIsUnread() {
        let content = merge([
            member(roomA, [readMarker(), event("a1", minutes: 0)], reachedStart: true),
            member(roomB, [event("b1", minutes: 5)], reachedStart: true),
        ])
        #expect(!render(content).contains("read"))
    }

    @Test func noReadMarkerWhenEveryItemIsRead() {
        let content = merge([
            member(roomA, [event("a1", minutes: 0), event("a2", minutes: 10), readMarker()], reachedStart: true),
            member(roomB, [event("b1", minutes: 5)], reachedStart: true),
        ])
        #expect(!render(content).contains("read"))
    }

    /// A read marker among the items the clamp hides still makes the room's
    /// later items unread.
    @Test func readMarkerAmongHiddenItemsStillMarksLaterItemsUnread() {
        let content = merge([
            member(roomA, [event("a0", minutes: -100), readMarker(), event("a1", minutes: -50), event("a2", minutes: 20)]),
            member(roomB, [event("b1", minutes: 0), event("b2", minutes: 10)]),
        ])
        #expect(render(content) == ["day:2026-11-10", "note:!b", "b1", "b2", "read", "note:!a", "a2"])
    }

    @Test func entriesAboveOneItemGoReadMarkerThenDayThenSourceNote() {
        // a1 on 2026-11-09 (read), b1 on 2026-11-10 (unread).
        let content = merge([
            member(roomA, [event("a1", minutes: -600)], reachedStart: true),
            member(roomB, [readMarker(), event("b1", minutes: 0)], reachedStart: true),
        ])
        #expect(render(content) == [
            "start", "day:2026-11-09", "note:!a", "a1", "read", "day:2026-11-10", "note:!b", "b1",
        ])
    }

    @Test func aLocalEchoAfterTheReadMarkerIsUnread() {
        let content = merge([
            member(roomA, [event("a1", minutes: 0), readMarker(), echo("echoA", minutes: 5)], reachedStart: true),
        ])
        #expect(render(content) == ["start", "day:2026-11-10", "a1", "read", "echoA"])
    }

    // MARK: Source notes

    @Test func noSourceNoteWhenOnlyOneRoomShows() {
        let content = merge([
            member(roomA, [event("a1", minutes: 0), event("a2", minutes: 1)], reachedStart: true),
            member(roomB, [], reachedStart: true),
        ])
        #expect(render(content) == ["start", "day:2026-11-10", "a1", "a2"])
    }

    /// Room B's only item is older than the boundary, so only room A shows.
    @Test func noSourceNoteWhenTheOtherRoomIsHidden() {
        let content = merge([
            member(roomA, [event("a1", minutes: 0), event("a2", minutes: 1)]),
            member(roomB, [event("b1", minutes: -30)]),
        ])
        #expect(render(content) == ["day:2026-11-10", "a1", "a2"])
    }

    @Test func sourceNoteCarriesItsRoomAndIsKeyedByTheFirstItemOfItsRun() {
        let content = merge([
            member(roomA, [event("a1", minutes: 0), event("a2", minutes: 1)], reachedStart: true),
            member(roomB, [event("b1", minutes: 5)], reachedStart: true),
        ])
        let notes = content.entries.filter { render(entry: $0).hasPrefix("note:") }
        #expect(notes == [
            .sourceChange(id: MergedTimelineEntryID.sourceChange(roomId: roomA, firstItemId: "a1"), roomId: roomA),
            .sourceChange(id: MergedTimelineEntryID.sourceChange(roomId: roomB, firstItemId: "b1"), roomId: roomB),
        ])
    }

    /// A new item at the newest end adds at most one note and changes no
    /// existing entry identifier.
    @Test func aNewItemAtTheNewestEndKeepsEveryExistingIdentifier() {
        let itemsA = [event("a1", minutes: 0), event("a2", minutes: 1)]
        let itemsB = [event("b1", minutes: 5)]
        let before = merge([member(roomA, itemsA, reachedStart: true), member(roomB, itemsB, reachedStart: true)])
        let sameRoom = merge([
            member(roomA, itemsA, reachedStart: true),
            member(roomB, itemsB + [event("b2", minutes: 6)], reachedStart: true),
        ])
        let otherRoom = merge([
            member(roomA, itemsA + [event("a3", minutes: 7)], reachedStart: true),
            member(roomB, itemsB, reachedStart: true),
        ])
        let beforeIds = before.entries.map(\.id)
        #expect(sameRoom.entries.map(\.id) == beforeIds + [MergedTimelineEntryID.item(roomId: roomB, itemId: "b2")])
        #expect(otherRoom.entries.map(\.id) == beforeIds + [
            MergedTimelineEntryID.sourceChange(roomId: roomA, firstItemId: "a3"),
            MergedTimelineEntryID.item(roomId: roomA, itemId: "a3"),
        ])
    }
}

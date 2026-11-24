import Foundation
@testable import Models
import Testing

/// MATRIX-224: the bound on the chat list's typing subscriptions.
struct ChatListTypingSlotsTests {
    @Test
    func firstRowSubscribesAndLastRowCancels() {
        var slots = ChatListTypingSlots(limit: 3)
        #expect(slots.appear(["!a"]) == .init(subscribe: ["!a"]))
        // A second row of the same room (a merged row) shares the slot.
        #expect(slots.appear(["!a"]) == .init())
        #expect(slots.disappear(["!a"]) == .init())
        #expect(slots.disappear(["!a"]) == .init(unsubscribe: ["!a"]))
        #expect(slots.subscribed.isEmpty)
        #expect(slots.onScreenCount == 0)
    }

    @Test
    func limitHoldsAndTheFirstWaitingRoomTakesTheFreeSlot() {
        var slots = ChatListTypingSlots(limit: 2)
        #expect(slots.appear(["!a", "!b", "!c", "!d"]) == .init(subscribe: ["!a", "!b"]))
        #expect(slots.waitingCount == 2)
        #expect(slots.disappear(["!a"]) == .init(subscribe: ["!c"], unsubscribe: ["!a"]))
        #expect(slots.subscribed == ["!b", "!c"])
    }

    @Test
    func waitingRoomThatLeavesNeverSubscribes() {
        var slots = ChatListTypingSlots(limit: 1)
        _ = slots.appear(["!a", "!b"])
        #expect(slots.disappear(["!b"]) == .init())
        #expect(slots.disappear(["!a"]) == .init(unsubscribe: ["!a"]))
        #expect(slots.subscribed.isEmpty)
        #expect(slots.waitingCount == 0)
    }

    @Test
    func disappearOfAnUnknownRoomDoesNothing() {
        var slots = ChatListTypingSlots(limit: 1)
        #expect(slots.disappear(["!x"]) == .init())
    }

    @Test
    func removeAllCancelsEverySubscription() {
        var slots = ChatListTypingSlots(limit: 5)
        _ = slots.appear(["!b", "!a"])
        #expect(slots.removeAll() == .init(unsubscribe: ["!a", "!b"]))
        #expect(slots.subscribed.isEmpty)
        #expect(slots.onScreenCount == 0)
    }

    /// The measured bound: a scroll from the top of a 500-chat list to the
    /// end and back, 25 rows on the screen and 10 more kept alive by the
    /// List, one row per step. The subscriptions never pass the limit, each
    /// step starts and cancels at most one, and none is left at the end.
    @Test
    func scrollThroughTheListStaysInTheBound() {
        let limit = 40
        let window = 35
        let rooms = (0 ..< 500).map { "!room\($0)" }
        var slots = ChatListTypingSlots(limit: limit)
        var subscribes = 0
        var cancels = 0
        var peak = 0

        func count(_ change: ChatListTypingSlots.Change) {
            subscribes += change.subscribe.count
            cancels += change.unsubscribe.count
            peak = max(peak, slots.subscribed.count)
        }

        count(slots.appear(Array(rooms[0 ..< window])))
        for top in 1 ... rooms.count - window {
            count(slots.disappear([rooms[top - 1]]))
            count(slots.appear([rooms[top + window - 1]]))
        }
        for top in stride(from: rooms.count - window - 1, through: 0, by: -1) {
            count(slots.disappear([rooms[top + window]]))
            count(slots.appear([rooms[top]]))
        }
        count(slots.disappear(Array(rooms[0 ..< window])))

        #expect(peak <= limit)
        #expect(peak == window)
        // One subscribe per row that came on the screen, one cancel per row
        // that left it.
        #expect(subscribes == window + 2 * (rooms.count - window))
        #expect(cancels == subscribes)
        #expect(slots.subscribed.isEmpty)
    }
}

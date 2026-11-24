import Foundation

/// Which chat-list rooms hold a typing subscription (MATRIX-224).
///
/// The chat list shows a typing state only for the rows on the screen, and
/// holds at most `limit` subscriptions. A room gets a slot when its first
/// row appears and gives it back when its last row disappears. A room that
/// appears while every slot is taken waits; the first waiting room takes
/// the next free slot.
///
/// Usage:
/// ```swift
/// var slots = ChatListTypingSlots(limit: 40)
/// slots.appear(["!a"]).subscribe // ["!a"]
/// slots.disappear(["!a"]).unsubscribe // ["!a"]
/// ```
public struct ChatListTypingSlots: Equatable, Sendable {
    /// What to start and stop after one call.
    public struct Change: Equatable, Sendable {
        /// The rooms that got a slot. Subscribe each.
        public var subscribe: [String] = []
        /// The rooms that gave their slot back. Cancel each subscription.
        public var unsubscribe: [String] = []

        public init(subscribe: [String] = [], unsubscribe: [String] = []) {
            self.subscribe = subscribe
            self.unsubscribe = unsubscribe
        }
    }

    /// The most subscriptions at one time.
    public let limit: Int
    /// The rooms with a slot.
    public private(set) var subscribed: Set<String> = []
    /// Rows on the screen by room ID. A merged row counts for each member.
    private var rowCounts: [String: Int] = [:]
    /// Rooms on the screen without a slot, first come first.
    private var waiting: [String] = []

    public init(limit: Int) {
        self.limit = max(0, limit)
    }

    /// The rooms with a row on the screen.
    public var onScreenCount: Int {
        rowCounts.count
    }

    /// The rooms on the screen that wait for a slot.
    public var waitingCount: Int {
        waiting.count
    }

    /// A row of the room is on the screen.
    public func isOnScreen(_ roomId: String) -> Bool {
        rowCounts[roomId] != nil
    }

    /// A row of each room appeared.
    public mutating func appear(_ roomIds: [String]) -> Change {
        var change = Change()
        for roomId in roomIds {
            let count = rowCounts[roomId, default: 0] + 1
            rowCounts[roomId] = count
            guard count == 1 else { continue }
            if subscribed.count < limit {
                subscribed.insert(roomId)
                change.subscribe.append(roomId)
            } else {
                waiting.append(roomId)
            }
        }
        return change
    }

    /// A row of each room disappeared.
    public mutating func disappear(_ roomIds: [String]) -> Change {
        var change = Change()
        for roomId in roomIds {
            guard let count = rowCounts[roomId] else { continue }
            guard count == 1 else {
                rowCounts[roomId] = count - 1
                continue
            }
            rowCounts[roomId] = nil
            guard subscribed.remove(roomId) != nil else {
                waiting.removeAll { $0 == roomId }
                continue
            }
            change.unsubscribe.append(roomId)
            if !waiting.isEmpty {
                let next = waiting.removeFirst()
                subscribed.insert(next)
                change.subscribe.append(next)
            }
        }
        return change
    }

    /// Gives every slot back, for example at sign-out.
    public mutating func removeAll() -> Change {
        let change = Change(unsubscribe: subscribed.sorted())
        subscribed.removeAll()
        rowCounts.removeAll()
        waiting.removeAll()
        return change
    }
}

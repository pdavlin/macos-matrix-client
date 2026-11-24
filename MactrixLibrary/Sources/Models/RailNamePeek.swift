import Foundation

/// The rail name peek (MATRIX-227), after Indigo's `TimelineCapsuleView`
/// feed-name peek: after a Go-menu key (⌘1…⌘9, ⇧⌘[, ⇧⌘]) selects a rail
/// item, the item's name shows next to the rail for `duration`, then
/// collapses. A click on the rail shows nothing and hides a name that shows.
///
/// A pure state machine. Every change takes the time, so the caller injects
/// the clock: the app passes `ContinuousClock.now`, the tests pass instants
/// they make. Nothing here reads a clock or waits.
public struct RailNamePeek: Equatable, Sendable {
    /// How long a name shows after its key.
    public static let duration: Duration = .seconds(1)

    /// One shown name.
    public struct Item: Equatable, Sendable, Identifiable {
        /// New for each key, so a key during a peek is a new peek, also for
        /// the same rail item.
        public let id: Int
        /// The rail item the key selected.
        public let filter: ChatListRailFilter
        /// When the name collapses.
        public let hidesAt: ContinuousClock.Instant
    }

    /// The shown name, or nil. It can be past `hidesAt` until `expire(at:)`
    /// runs; `item(at:)` reads it with the time.
    public private(set) var item: Item?

    /// The last item's ID.
    private var serial = 0

    public init() {}

    /// A Go-menu key selected `filter` at `now`: its name shows, in place of
    /// any name that shows, and the time starts again.
    public mutating func show(_ filter: ChatListRailFilter, at now: ContinuousClock.Instant) {
        serial &+= 1
        item = Item(id: serial, filter: filter, hidesAt: now + Self.duration)
    }

    /// The name that shows at `now`: nil once its time is over.
    public func item(at now: ContinuousClock.Instant) -> Item? {
        guard let item, now < item.hidesAt else { return nil }
        return item
    }

    /// Collapses the name if its time is over at `now`. A name shown by a
    /// later key keeps its own time.
    public mutating func expire(at now: ContinuousClock.Instant) {
        if item != nil, item(at: now) == nil {
            item = nil
        }
    }

    /// Collapses the name at once: a click on the rail.
    public mutating func hide() {
        item = nil
    }
}

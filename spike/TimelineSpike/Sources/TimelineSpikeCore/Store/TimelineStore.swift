import Foundation
import Observation

/// The loaded window of synthetic events, plus derived layout flags.
///
/// Invariants, relied on by the drivers and by the drift measurement:
///
/// 1. `items` is contiguous on the generator index line. Item `n` has
///    `id.rawValue == oldestIndex + n`.
/// 2. `items` is strictly ascending by timestamp.
/// 3. Mutation never inserts, removes or reorders items. Only `prepend(count:)` changes
///    the item count, and only at the front.
///
/// The calendar is fixed to UTC on purpose. Day separators must land on the same events on
/// every machine, otherwise S-13 and S-14 measure different layouts.
@MainActor
@Observable
public final class TimelineStore {
    public private(set) var items: [TimelineItem]
    public private(set) var oldestIndex: Int
    public private(set) var newestIndex: Int
    public private(set) var prependedBatchCount = 0
    public private(set) var prependedEventCount = 0
    public private(set) var appliedMutationCount = 0

    public let generator: SyntheticEventGenerator
    public let calendar: Calendar

    public init(seed: UInt64, initialEventCount: Int, calendar: Calendar = .spikeUTC) {
        precondition(initialEventCount > 0, "initialEventCount must be positive")
        self.generator = SyntheticEventGenerator(seed: seed)
        self.calendar = calendar
        self.oldestIndex = 0
        self.newestIndex = initialEventCount - 1
        self.items = generator.events(in: 0 ..< initialEventCount).map { TimelineItem(event: $0) }
        annotate(from: 0, through: items.count - 1)
    }

    // MARK: - Lookup

    /// The array position of an identifier, or `nil` when the event is outside the window.
    public func itemIndex(for id: EventID) -> Int? {
        let position = id.rawValue - oldestIndex
        return items.indices.contains(position) ? position : nil
    }

    public func event(with id: EventID) -> SpikeEvent? {
        itemIndex(for: id).map { items[$0].event }
    }

    /// The item-index range spanned by a set of on-screen identifiers.
    ///
    /// A renderer knows which rows are visible but not where they sit in `items`, and the
    /// mutation driver needs the range to split on-screen from off-screen targets. Only the
    /// extremes matter, so this is O(n) over the visible rows with no allocation, not a
    /// sort.
    ///
    /// Identifiers outside the loaded window are ignored rather than treated as an error: a
    /// prepend can land between the renderer reading its visible set and this call.
    /// Returns `nil` when nothing in `ids` is loaded.
    public func visibleRange(spanning ids: some Sequence<EventID>) -> Range<Int>? {
        var lowest: Int?
        var highest: Int?
        for id in ids {
            guard let index = itemIndex(for: id) else { continue }
            lowest = min(lowest ?? index, index)
            highest = max(highest ?? index, index)
        }
        guard let lowest, let highest else { return nil }
        return lowest ..< (highest + 1)
    }

    // MARK: - Back-pagination

    /// Prepends a batch of older events and returns the inserted item-index range.
    ///
    /// The returned range is always `0 ..< count`. Everything that was loaded shifts down
    /// by `count`, which is exactly the shift a renderer must absorb without moving the
    /// visible content.
    @discardableResult
    public func prepend(count: Int) -> Range<Int> {
        guard count > 0 else { return 0 ..< 0 }
        let newOldest = oldestIndex - count
        let batch = generator.events(in: newOldest ..< oldestIndex)
        items.insert(contentsOf: batch.map { TimelineItem(event: $0) }, at: 0)
        oldestIndex = newOldest
        prependedBatchCount += 1
        prependedEventCount += count
        // Re-derive the seam: the batch itself, plus the item that used to be first and may
        // no longer open a day or a sender run.
        annotate(from: 0, through: min(count, items.count - 1))
        return 0 ..< count
    }

    // MARK: - Mutation

    /// Applies one mutation. Returns the touched item index, or `nil` when the target is
    /// outside the loaded window or the mutation does not apply to its content.
    @discardableResult
    public func apply(_ mutation: Mutation) -> Int? {
        guard let index = itemIndex(for: mutation.target) else { return nil }
        switch mutation {
        case .editText(_, let body):
            guard items[index].event.content.isText else { return nil }
            items[index].event.content = .text(body)
            items[index].event.editCount += 1
        case .addReaction(_, let key):
            if let existing = items[index].event.reactions.firstIndex(where: { $0.key == key }) {
                items[index].event.reactions[existing].count += 1
            } else {
                items[index].event.reactions.append(Reaction(key: key, count: 1))
            }
        case .removeReaction(_, let key):
            guard let existing = items[index].event.reactions
                .firstIndex(where: { $0.key == key }) else { return nil }
            items[index].event.reactions[existing].count -= 1
            if items[index].event.reactions[existing].count <= 0 {
                items[index].event.reactions.remove(at: existing)
            }
        }
        appliedMutationCount += 1
        return index
    }

    // MARK: - Derived layout flags

    /// Recomputes `startsSenderRun` and `daySeparator` over a closed item-index range.
    ///
    /// A run breaks on a new sender, on a new day, or after five minutes of silence.
    private func annotate(from start: Int, through end: Int) {
        guard !items.isEmpty else { return }
        let lower = max(0, start)
        let upper = min(items.count - 1, end)
        guard lower <= upper else { return }

        for index in lower ... upper {
            let event = items[index].event
            let previous: SpikeEvent? = index > 0 ? items[index - 1].event : nil
            let day = calendar.startOfDay(for: event.timestamp)
            let previousDay = previous.map { calendar.startOfDay(for: $0.timestamp) }
            let opensDay = previousDay != day
            items[index].daySeparator = opensDay ? day : nil

            let sameSender = previous?.sender.id == event.sender.id
            let closeInTime: Bool = if let previous {
                event.timestamp.timeIntervalSince(previous.timestamp) < 300
            } else {
                false
            }
            items[index].startsSenderRun = opensDay || !sameSender || !closeInTime
        }
    }
}

public extension Calendar {
    /// A fixed Gregorian/UTC calendar so day separators are machine independent.
    static let spikeUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
}

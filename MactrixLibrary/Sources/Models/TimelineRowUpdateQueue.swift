import Foundation

/// Content-only row updates waiting for frame budget (MATRIX-57).
///
/// A storm tick mutates more rows than one frame can redraw, so the container
/// paces the work across frames instead of applying all of it at once. This
/// queue holds what is owed and hands back the next slice.
///
/// Entries are keyed by row **identity**, never by index: a structural change
/// between the enqueue and the drain renumbers every row after it, so a queued
/// index would address a different row by the time it is applied. The caller
/// supplies the identity-to-index resolution at drain time.
///
/// Generic over the payload, so the row type stays with the container and this
/// stays testable without AppKit.
public struct TimelineRowUpdateQueue<Payload> {
    /// One queued update, before its identity is resolved to a row index.
    public struct Entry {
        public let uniqueId: String
        public let payload: Payload
    }

    /// A queued update whose identity still names a row.
    public struct Resolved {
        public let uniqueId: String
        public let payload: Payload
        public let index: Int
        public let isVisible: Bool
    }

    /// Insertion order, which is the order rows are applied within a
    /// visibility group.
    private var entries: [Entry] = []
    /// Identity to position in `entries`, so a repeat enqueue is O(1).
    private var positions: [String: Int] = [:]

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// Queues one update, superseding any update already queued for that row.
    ///
    /// Latest wins: two updates to one row describe the same row at two points
    /// in time, and only the newest is worth the redraw. The entry keeps its
    /// original position, so a row that mutates on every tick cannot starve
    /// the rows queued behind it.
    public mutating func enqueue(uniqueId: String, payload: Payload) {
        if let position = positions[uniqueId] {
            entries[position] = Entry(uniqueId: uniqueId, payload: payload)
            return
        }
        positions[uniqueId] = entries.count
        entries.append(Entry(uniqueId: uniqueId, payload: payload))
    }

    /// Drops queued updates for rows that left the timeline.
    ///
    /// The drain drops an unresolvable identity on its own, so this only
    /// matters when the same identity can return: a re-inserted row must not
    /// inherit the payload queued against the copy that was removed.
    public mutating func remove(uniqueIds: some Sequence<String>) {
        let dropped = Set(uniqueIds)
        guard entries.contains(where: { dropped.contains($0.uniqueId) }) else { return }
        entries.removeAll { dropped.contains($0.uniqueId) }
        reindex()
    }

    public mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
        positions.removeAll(keepingCapacity: true)
    }

    /// Takes the next `limit` updates to apply, visible rows first.
    ///
    /// `resolve` maps identity to the row index it currently occupies and
    /// returns nil for a row the timeline no longer holds. Unresolvable
    /// entries are dropped rather than returned, which is how the queue
    /// survives a structural change that lands between the enqueue and the
    /// drain.
    ///
    /// Visible rows go first because an update the reader can see is the one
    /// whose latency is perceived.
    ///
    /// Returned entries leave the queue: the caller owns applying them.
    public mutating func take(
        limit: Int,
        resolve: (String) -> Int?,
        isVisible: (Int) -> Bool
    ) -> [Resolved] {
        guard limit > 0, !entries.isEmpty else { return [] }

        var visible: [Resolved] = []
        var offscreen: [Resolved] = []
        var stale: Set<String> = []

        for entry in entries {
            guard let index = resolve(entry.uniqueId) else {
                stale.insert(entry.uniqueId)
                continue
            }
            let onScreen = isVisible(index)
            let resolved = Resolved(
                uniqueId: entry.uniqueId,
                payload: entry.payload,
                index: index,
                isVisible: onScreen
            )
            if onScreen {
                visible.append(resolved)
            } else {
                offscreen.append(resolved)
            }
        }

        let taken = Array((visible + offscreen).prefix(limit))
        var consumed = stale
        consumed.formUnion(taken.map(\.uniqueId))
        entries.removeAll { consumed.contains($0.uniqueId) }
        reindex()
        return taken
    }

    private mutating func reindex() {
        positions.removeAll(keepingCapacity: true)
        for (position, entry) in entries.enumerated() {
            positions[entry.uniqueId] = position
        }
    }
}

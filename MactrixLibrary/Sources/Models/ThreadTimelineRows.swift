import CoreGraphics
import Foundation

/// The "N replies" divider row of a thread timeline (MATRIX-183): a
/// fixed-height virtual row right after the thread root, made by the app.
public enum ThreadRepliesDivider {
    /// The row height at every width. The row view
    /// (`UI.ThreadRepliesDividerRow`) is one line in a frame of
    /// `ThreadToken.repliesDividerHeight`; a test keeps the two equal.
    public static let rowHeight: CGFloat = 28

    /// The prefix of the row identifier.
    public static let rowIdPrefix = "mactrix.thread.replies"

    /// The row identifier. It carries the count, as the container's typing
    /// row carries its names: a new count is a new row, so no height or view
    /// made for the old text is used again.
    public static func rowId(count: Int) -> String {
        "\(rowIdPrefix):\(count)"
    }

    /// The divider row for `count` replies.
    public static func row(count: Int) -> TimelineRow {
        .virtual(uniqueId: rowId(count: count), item: .threadReplies(count: count))
    }

    /// `rows` (newest first) with the divider right after the root: in
    /// display order, at the root's index, so the root moves one index up
    /// (older). Unchanged when there is no anchor, no reply, or no root row.
    public static func inserting(into rows: [TimelineRow], anchor: ThreadDividerAnchor?) -> [TimelineRow] {
        guard let anchor, anchor.replyCount > 0,
              let rootIndex = rows.firstIndex(where: { $0.uniqueId == anchor.rootRowId })
        else { return rows }
        var result = rows
        result.insert(row(count: anchor.replyCount), at: rootIndex)
        return result
    }
}

/// What the thread panel reads from a thread timeline's items (MATRIX-183).
public struct ThreadTimelineFacts: Equatable, Sendable {
    /// The reply count, or nil while no event is loaded.
    public var replyCount: Int?
    /// The row identifier of the thread root, or nil while the root is not
    /// loaded.
    public var rootRowId: String?

    public init(replyCount: Int? = nil, rootRowId: String? = nil) {
        self.replyCount = replyCount
        self.rootRowId = rootRowId
    }

    /// Where the "N replies" divider goes, or nil while the root or the
    /// count is not known.
    public var dividerAnchor: ThreadDividerAnchor? {
        guard let rootRowId, let replyCount else { return nil }
        return ThreadDividerAnchor(rootRowId: rootRowId, replyCount: replyCount)
    }
}

/// Where the divider goes and what it says (MATRIX-183).
public struct ThreadDividerAnchor: Equatable, Sendable {
    /// The row identifier of the thread root.
    public let rootRowId: String
    /// The reply count the divider shows.
    public let replyCount: Int

    public init(rootRowId: String, replyCount: Int) {
        self.rootRowId = rootRowId
        self.replyCount = replyCount
    }
}

/// A thread timeline's rows with the "N replies" divider, kept in step with
/// the thread timeline's own display changes (MATRIX-183).
///
/// The thread timeline publishes changes in its own index space, which has
/// no divider. This mirrors those changes onto a copy of its rows, inserts
/// the divider, and states the difference to the rows the container holds
/// with `TimelineRowDiff`, the path the merged timeline's client-made rows
/// take. So the container keeps its diff-sized updates, its height cache,
/// and its scroll anchor.
///
/// Cost per drain: the changes, plus one O(n) diff over the thread's rows.
/// A thread is small next to a room timeline.
public struct ThreadTimelineRows {
    /// The rows the container holds: the thread's rows with the divider.
    public private(set) var rows: [TimelineRow] = []
    /// The thread timeline's rows, without the divider.
    private var baseRows: [TimelineRow] = []
    private var anchor: ThreadDividerAnchor?

    public init() {}

    /// Starts again from the thread timeline's whole row list.
    ///
    /// - Returns: the rows with the divider.
    public mutating func start(base: [TimelineRow], anchor: ThreadDividerAnchor?) -> [TimelineRow] {
        baseRows = base
        self.anchor = anchor
        rows = ThreadRepliesDivider.inserting(into: base, anchor: anchor)
        return rows
    }

    /// Applies the thread timeline's display changes and returns the changes
    /// to the rows with the divider.
    ///
    /// A reset, or a change whose index does not match the copy, makes the
    /// result one `.reset`: the container then rebuilds from `start(base:anchor:)`.
    ///
    /// - Parameters:
    ///   - updates: the thread timeline's changes since the last call, in
    ///     its own display indices.
    ///   - newAnchor: the anchor after the changes.
    /// - Returns: the changes, empty when nothing changed.
    public mutating func apply(
        _ updates: [TimelineRowDisplayUpdate],
        anchor newAnchor: ThreadDividerAnchor?
    ) -> [TimelineRowDisplayUpdate] {
        guard !updates.isEmpty || newAnchor != anchor else { return [] }

        // Rows whose content can differ from the copy the container holds:
        // replaced rows, and inserted rows, because an identity the container
        // already holds can come back with new content.
        var changedIds = Set<String>()
        var mustReset = false
        changes: for update in updates {
            switch update.change {
            case .reset:
                mustReset = true
                break changes
            case let .insert(index, count):
                guard update.rows.count == count, index >= 0, index <= baseRows.count else {
                    mustReset = true
                    break changes
                }
                baseRows.insert(contentsOf: update.rows, at: index)
                changedIds.formUnion(update.rows.map(\.uniqueId))
            case let .remove(index, count):
                guard count > 0, index >= 0, index + count <= baseRows.count else {
                    mustReset = true
                    break changes
                }
                baseRows.removeSubrange(index ..< index + count)
            case let .update(index):
                guard let row = update.rows.first, baseRows.indices.contains(index) else {
                    mustReset = true
                    break changes
                }
                baseRows[index] = row
                changedIds.insert(row.uniqueId)
            }
        }

        anchor = newAnchor
        if mustReset {
            return [TimelineRowDisplayUpdate(change: .reset)]
        }

        let newRows = ThreadRepliesDivider.inserting(into: baseRows, anchor: newAnchor)
        let result = TimelineRowDiff.updates(
            from: rows,
            to: newRows,
            id: { (row: TimelineRow) -> String in row.uniqueId },
            hasSameContent: { (old: TimelineRow, _: TimelineRow) -> Bool in !changedIds.contains(old.uniqueId) },
            row: { (row: TimelineRow) -> TimelineRow in row }
        )
        rows = newRows
        return result
    }
}

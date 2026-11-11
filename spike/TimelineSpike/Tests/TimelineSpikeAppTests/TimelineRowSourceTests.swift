import AppKit
import Foundation
import Models
@testable import ProductionTimeline
import Testing

/// MATRIX-142 Wave 2: the production timeline container driven through the
/// row-based path of `TimelineRowSource`, as a merged chat drives it.
///
/// The source here is a stand-in that queues `TimelineRowDiff` updates, the
/// same changes `MergedLiveTimeline.drainRowChanges()` hands over. The rows
/// are virtual (day dividers and source notes), so no SDK event is needed.
@MainActor
@Suite("Timeline row source", .serialized)
struct TimelineRowSourceTests {
    // MARK: - Fixture

    /// A row source that holds rows and queues the diff to each new set.
    @MainActor
    final class RowSource: TimelineRowSource {
        private(set) var rows: [TimelineRow] = []
        var pending: [TimelineRowDisplayUpdate] = []

        var displayRows: [TimelineRow] {
            rows
        }

        func drainRowUpdates() -> [TimelineRowDisplayUpdate] {
            defer { pending.removeAll() }
            return pending
        }

        func discardRowUpdates() {
            pending.removeAll()
        }

        func timeline(for _: TimelineRow) -> LiveTimeline? {
            nil
        }

        var actionTimelines: [LiveTimeline] {
            []
        }

        var typingNames: [String] {
            []
        }

        var isPaginating: Bool {
            false
        }

        var paginationFailure: String? {
            nil
        }

        var scrollToBottomRequests: Int {
            0
        }

        func setAtBottom(_: Bool) {}

        func paginateBackwards() async {}

        var focusTarget: TimelineEventReference? {
            nil
        }

        func rowId(of _: TimelineEventReference) -> String? {
            nil
        }

        /// Moves to `next` and queues the changes, as the merged timeline
        /// does after a recompute.
        func show(_ next: [TimelineRow]) {
            pending.append(contentsOf: TimelineRowDiff.updates(
                from: rows,
                to: next,
                id: { (row: TimelineRow) -> String in row.uniqueId },
                hasSameContent: { (lhs: TimelineRow, rhs: TimelineRow) -> Bool in
                    TimelineRowSourceTests.label(of: lhs) == TimelineRowSourceTests.label(of: rhs)
                },
                row: { (row: TimelineRow) -> TimelineRow in row }
            ))
            rows = next
        }
    }

    fileprivate static func label(of row: TimelineRow) -> MergedSourceLabel? {
        guard case let .virtual(_, .mergedSource(label)) = row else { return nil }
        return label
    }

    private static func day(_ id: String) -> TimelineRow {
        .virtual(uniqueId: "day:\(id)", item: .dateDivider(date: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    private static func note(_ id: String, title: String = "Slack") -> TimelineRow {
        let sourceLabel = MergedSourceLabel(roomId: "!\(id):x", network: nil, title: title, detail: nil)
        return .virtual(uniqueId: "note:\(id)", item: .mergedSource(sourceLabel))
    }

    /// A controller over `source`, on screen in a borderless window.
    @MainActor
    private final class Mounted {
        let window: NSWindow
        let controller: TimelineViewController

        init(source: RowSource) {
            _ = NSApplication.shared
            controller = TimelineViewController(
                coordinator: TimelineViewRepresentable.Coordinator(appState: AppState(), windowState: WindowState()),
                source: source
            )
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.borderless],
                backing: .buffered,
                defer: true
            )
            window.isReleasedWhenClosed = false
            controller.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
            window.contentView?.addSubview(controller.view)
            controller.view.layoutSubtreeIfNeeded()
        }

        var rowIds: [String] {
            controller.timelineRows.map(\.uniqueId)
        }

        func close() {
            window.close()
        }
    }

    // MARK: - Tests

    @Test("The first rows arrive as a reset")
    func firstRowsArriveAsAReset() {
        let source = RowSource()
        let mounted = Mounted(source: source)
        defer { mounted.close() }

        source.show([Self.note("a"), Self.day("1")])
        mounted.controller.applyPendingTimelineChanges()

        #expect(mounted.rowIds == ["note:a", "day:1"])
    }

    @Test("Rows the source starts with are shown, and its old changes are not replayed")
    func startsFromTheSourceRows() {
        let source = RowSource()
        source.show([Self.note("a"), Self.day("1")])
        let mounted = Mounted(source: source)
        defer { mounted.close() }

        mounted.controller.applyPendingTimelineChanges()

        #expect(mounted.rowIds == ["note:a", "day:1"])
    }

    @Test("A newer row is inserted at the newest end")
    func newerRowInsertsAtTheNewestEnd() {
        let source = RowSource()
        let mounted = Mounted(source: source)
        defer { mounted.close() }
        source.show([Self.note("a"), Self.day("1")])
        mounted.controller.applyPendingTimelineChanges()

        source.show([Self.note("b"), Self.note("a"), Self.day("1")])
        mounted.controller.applyPendingTimelineChanges()

        #expect(mounted.rowIds == ["note:b", "note:a", "day:1"])
    }

    @Test("Older rows from a back-pagination are inserted at the oldest end")
    func olderRowsInsertAtTheOldestEnd() {
        let source = RowSource()
        let mounted = Mounted(source: source)
        defer { mounted.close() }
        source.show([Self.note("a"), Self.day("1")])
        mounted.controller.applyPendingTimelineChanges()

        source.show([Self.note("a"), Self.day("1"), Self.note("b"), Self.day("0")])
        mounted.controller.applyPendingTimelineChanges()

        #expect(mounted.rowIds == ["note:a", "day:1", "note:b", "day:0"])
    }

    /// A merge recompute can move a row between member runs: the diff
    /// removes it and inserts it again in one batch.
    @Test("A moved row is removed and inserted in one batch")
    func movedRowAppliesInOneBatch() {
        let source = RowSource()
        let mounted = Mounted(source: source)
        defer { mounted.close() }
        source.show([Self.note("a"), Self.note("b"), Self.day("1")])
        mounted.controller.applyPendingTimelineChanges()

        source.show([Self.note("b"), Self.note("a"), Self.day("1")])
        mounted.controller.applyPendingTimelineChanges()

        #expect(mounted.rowIds == ["note:b", "note:a", "day:1"])
    }

    @Test("A changed row keeps its place and waits for the drain")
    func changedRowQueuesAContentUpdate() {
        let source = RowSource()
        let mounted = Mounted(source: source)
        defer { mounted.close() }
        source.show([Self.note("a", title: "Slack"), Self.day("1")])
        mounted.controller.applyPendingTimelineChanges()

        source.show([Self.note("a", title: "Google Chat"), Self.day("1")])
        mounted.controller.applyPendingTimelineChanges()

        #expect(mounted.rowIds == ["note:a", "day:1"])
        #expect(mounted.controller.pendingRowUpdates.count == 1)
    }

    /// MATRIX-130: an insert of a row the table already holds must resync,
    /// not raise inside the snapshot.
    @Test("An insert of a row the table holds resyncs from the source")
    func repeatedInsertResyncs() {
        let source = RowSource()
        let mounted = Mounted(source: source)
        defer { mounted.close() }
        source.show([Self.note("a"), Self.day("1")])
        mounted.controller.applyPendingTimelineChanges()

        source.pending = [TimelineRowDisplayUpdate(change: .insert(index: 0, count: 1), rows: [Self.note("a")])]
        mounted.controller.applyPendingTimelineChanges()

        #expect(mounted.rowIds == ["note:a", "day:1"])
    }

    @Test("A source with no rows left resets to empty")
    func emptyRowsReset() {
        let source = RowSource()
        let mounted = Mounted(source: source)
        defer { mounted.close() }
        source.show([Self.note("a"), Self.day("1")])
        mounted.controller.applyPendingTimelineChanges()

        source.show([])
        mounted.controller.applyPendingTimelineChanges()

        #expect(mounted.rowIds.isEmpty)
    }
}

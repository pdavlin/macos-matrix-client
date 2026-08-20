import CoreGraphics
import Foundation
import Testing
@testable import TimelineSpikeApp
import TimelineSpikeCore

@Suite("Row height cache")
struct RowHeightCacheTests {
    private let model = SpikeRowHeightModel(measurer: StubMeasurer())
    /// Wraps the text column at exactly 200pt, so the stub measurer fits 20 characters a line.
    private let rowWidth: CGFloat = 288

    private func item(
        id: Int,
        characters: Int = 10,
        reactions: [Reaction] = [],
        editCount: Int = 0,
        startsSenderRun: Bool = true
    ) -> TimelineItem {
        let event = SpikeEvent(
            id: EventID(id),
            sender: SpikeSender.roster[abs(id) % SpikeSender.roster.count],
            timestamp: Date(timeIntervalSince1970: TimeInterval(id) * 60),
            content: .text(
                TextBody(paragraphs: [String(repeating: "a", count: characters)], lineCount: 1)
            ),
            reactions: reactions,
            editCount: editCount
        )
        return TimelineItem(event: event, startsSenderRun: startsSenderRun)
    }

    private func window(_ ids: Range<Int>) -> [TimelineItem] {
        ids.map { item(id: $0) }
    }

    @Test("A rebuild measures every row and totals them")
    func rebuild() {
        var cache = RowHeightCache()
        let items = window(0 ..< 5)
        cache.rebuild(items: items, rowWidth: rowWidth, model: model)

        #expect(cache.rowCount == 5)
        #expect(cache.height(row: 0) == 42)
        #expect(cache.totalHeight == 210)
        #expect(cache.rowWidth == rowWidth)
    }

    @Test("An out-of-range row reports zero instead of trapping")
    func outOfRange() {
        var cache = RowHeightCache()
        cache.rebuild(items: window(0 ..< 2), rowWidth: rowWidth, model: model)
        #expect(cache.height(row: 7) == 0)
        #expect(cache.height(row: -1) == 0)
    }

    @Test("A prepend returns the height the document gained")
    func insertPrefix() {
        var cache = RowHeightCache()
        cache.rebuild(items: window(0 ..< 3), rowWidth: rowWidth, model: model)
        let older = [item(id: -2, characters: 60), item(id: -1)]

        let gained = cache.insertPrefix(older[...], model: model)

        // A three-line row at 74 and a one-line row at 42.
        #expect(gained == 116)
        #expect(cache.rowCount == 5)
        #expect(cache.height(row: 0) == 74)
        #expect(cache.height(row: 1) == 42)
        #expect(cache.height(row: 2) == 42)
        #expect(cache.totalHeight == 242)
    }

    @Test("An empty prepend changes nothing")
    func emptyPrefix() {
        var cache = RowHeightCache()
        cache.rebuild(items: window(0 ..< 3), rowWidth: rowWidth, model: model)
        let gained = cache.insertPrefix([TimelineItem]()[...], model: model)
        #expect(gained == 0)
        #expect(cache.rowCount == 3)
    }

    @Test("An edit that changes the height is reported with its delta")
    func editChangesHeight() {
        var cache = RowHeightCache()
        var items = window(0 ..< 4)
        cache.rebuild(items: items, rowWidth: rowWidth, model: model)

        items[2] = item(id: 2, characters: 60, editCount: 1)
        let (changedRows, changes) = cache.refresh(items: items, model: model)

        // 74 for three lines, plus 20 for the edit marker and its spacing, less the old 42.
        #expect(changedRows == [2])
        #expect(changes == [RowHeightCache.HeightChange(row: 2, delta: 52)])
        #expect(cache.height(row: 2) == 94)
        #expect(cache.totalHeight == 220)
    }

    @Test("Content that changes without changing the height still marks the row dirty")
    func contentChangeWithoutHeightChange() {
        var cache = RowHeightCache()
        // Already edited once, so the "edited" marker is present before and after.
        var items = (0 ..< 3).map { item(id: $0, editCount: 1) }
        cache.rebuild(items: items, rowWidth: rowWidth, model: model)

        // Same length, so the row is the same height, but the cell must still be re-hosted.
        items[1] = item(id: 1, characters: 10, editCount: 2)
        let (changedRows, changes) = cache.refresh(items: items, model: model)

        #expect(changedRows == [1])
        #expect(changes.isEmpty)
    }

    @Test("The first reaction adds a row; a bigger tally on the same key does not")
    func reactionChanges() {
        var cache = RowHeightCache()
        var items = window(0 ..< 3)
        cache.rebuild(items: items, rowWidth: rowWidth, model: model)

        items[0] = item(id: 0, reactions: [Reaction(key: "👍", count: 1)])
        let first = cache.refresh(items: items, model: model)
        #expect(first.changes == [RowHeightCache.HeightChange(row: 0, delta: 24)])

        items[0] = item(id: 0, reactions: [Reaction(key: "👍", count: 2)])
        let second = cache.refresh(items: items, model: model)
        #expect(second.changedRows.isEmpty)
        #expect(second.changes.isEmpty)

        items[0] = item(id: 0, reactions: [])
        let third = cache.refresh(items: items, model: model)
        #expect(third.changes == [RowHeightCache.HeightChange(row: 0, delta: -24)])
        #expect(cache.height(row: 0) == 42)
    }

    @Test("A re-annotated seam row is caught after a prepend")
    func senderRunFlagChange() {
        var cache = RowHeightCache()
        var items = window(0 ..< 3)
        cache.rebuild(items: items, rowWidth: rowWidth, model: model)

        // The store re-annotates the row that used to be first; it can stop opening a run.
        items[0] = item(id: 0, startsSenderRun: false)
        let (changedRows, changes) = cache.refresh(items: items, model: model)

        #expect(changedRows == [0])
        #expect(changes == [RowHeightCache.HeightChange(row: 0, delta: -18)])
    }

    @Test("Untouched rows are not re-measured")
    func quietRows() {
        var cache = RowHeightCache()
        let items = window(0 ..< 200)
        cache.rebuild(items: items, rowWidth: rowWidth, model: model)

        let (changedRows, changes) = cache.refresh(items: items, model: model)
        #expect(changedRows.isEmpty)
        #expect(changes.isEmpty)
    }

    @Test("A refresh against a differently sized window is refused rather than misaligned")
    func lengthMismatchIsIgnored() {
        var cache = RowHeightCache()
        cache.rebuild(items: window(0 ..< 3), rowWidth: rowWidth, model: model)

        let (changedRows, changes) = cache.refresh(items: window(0 ..< 5), model: model)
        #expect(changedRows.isEmpty)
        #expect(changes.isEmpty)
        #expect(cache.rowCount == 3)
    }

    @Test("Fingerprints ignore what cannot change a height")
    func fingerprintScope() {
        let plain = SpikeRowFingerprint(item: item(id: 1))
        let sameHeight = SpikeRowFingerprint(
            item: item(id: 1, reactions: [], editCount: 0, startsSenderRun: true)
        )
        #expect(plain == sameHeight)

        let edited = SpikeRowFingerprint(item: item(id: 1, editCount: 1))
        #expect(plain != edited)

        let reacted = SpikeRowFingerprint(item: item(id: 1, reactions: [Reaction(key: "🎉", count: 1)]))
        #expect(plain != reacted)
    }
}

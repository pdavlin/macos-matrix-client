import CoreGraphics
@testable import Models
import Testing

/// MATRIX-98: the per-width height cache behind the iOS timeline.
struct TimelineWidthHeightCacheTests {
    private static func row(_ id: String) -> TimelineRow {
        .message(uniqueId: id, event: MockEventTimelineItem(), kind: .text, heightFingerprint: .stub())
    }

    /// Height falls as width grows, so every width gives a distinct answer.
    private static func measure(_: TimelineRow, _ width: CGFloat) -> CGFloat {
        10_000 / width
    }

    @Test
    func returningToAKeptWidthMeasuresNothing() {
        var cache = TimelineWidthHeightCache<Int>()
        let row = Self.row("a")
        _ = cache.height(for: row, width: 100, tokens: 0, revision: 0, measure: Self.measure)
        _ = cache.height(for: row, width: 200, tokens: 0, revision: 0, measure: Self.measure)
        #expect(cache.stats.misses == 2)

        let back = cache.height(for: row, width: 100, tokens: 0, revision: 0, measure: Self.measure)
        #expect(back == 100)
        #expect(cache.stats.misses == 2)
        #expect(cache.stats.hits == 1)
    }

    @Test
    func theLeastRecentlyUsedWidthGoesFirst() {
        var cache = TimelineWidthHeightCache<Int>(widthCapacity: 2)
        let row = Self.row("a")
        for width: CGFloat in [100, 200, 100, 300] {
            _ = cache.height(for: row, width: width, tokens: 0, revision: 0, measure: Self.measure)
        }
        #expect(cache.widths == [100, 300])
        #expect(cache.cachedHeight(forRowId: "a", width: 200) == nil)
        #expect(cache.cachedHeight(forRowId: "a", width: 100) == 100)
    }

    @Test
    func validHeightNeverMeasuresAndMissesOnAStaleRevision() {
        var cache = TimelineWidthHeightCache<Int>()
        let row = Self.row("a")
        #expect(cache.validHeight(for: row, width: 100, tokens: 0, revision: 0) == nil)
        _ = cache.height(for: row, width: 100, tokens: 0, revision: 0, measure: Self.measure)
        #expect(cache.validHeight(for: row, width: 100, tokens: 0, revision: 0) == 100)
        #expect(cache.validHeight(for: row, width: 100, tokens: 0, revision: 1) == nil)
        #expect(cache.validHeight(for: row, width: 100, tokens: 1, revision: 0) == nil)
        #expect(cache.stats.misses == 1)
        // A stale height is still a placeholder.
        #expect(cache.cachedHeight(forRowId: "a", width: 100) == 100)
    }

    @Test
    func invalidatingARowDropsItAtEveryWidth() {
        var cache = TimelineWidthHeightCache<Int>()
        for id in ["a", "b"] {
            for width: CGFloat in [100, 200] {
                _ = cache.height(for: Self.row(id), width: width, tokens: 0, revision: 0, measure: Self.measure)
            }
        }
        cache.invalidate(rowId: "a")
        #expect(cache.cachedHeight(forRowId: "a", width: 100) == nil)
        #expect(cache.cachedHeight(forRowId: "a", width: 200) == nil)
        #expect(cache.count(atWidth: 100) == 1)

        cache.retain(rowIds: [])
        #expect(cache.count(atWidth: 200) == 0)

        cache.invalidateAll()
        #expect(cache.widths.isEmpty)
    }
}

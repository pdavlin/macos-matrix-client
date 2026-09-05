import CoreGraphics
import Foundation
@testable import Models
import Testing

/// S-32: the pure measurement math and the height cache.
///
/// The measurement source is injected, so these tests drive the pipeline with
/// deterministic measurers modelling the row shapes the acceptance names:
/// one-line bodies (width-independent height), multi-paragraph bodies
/// (wrapping arithmetic, so height moves with width), and media rows
/// (aspect-clamped image height).
struct TimelineRowMeasurementTests {
    // MARK: - Deterministic measurers

    /// A single line of body text: one line box plus vertical padding, at any
    /// width wide enough to hold it.
    private static func oneLineMeasurer(
        lineHeight: CGFloat = 16,
        padding: CGFloat = 8
    ) -> (TimelineRow, CGFloat) -> CGFloat {
        { _, _ in lineHeight + padding }
    }

    /// A multi-paragraph body wrapped at a fixed glyph width: each paragraph
    /// occupies `ceil(characters * glyphWidth / width)` line boxes.
    private static func paragraphMeasurer(
        paragraphs: [Int],
        glyphWidth: CGFloat = 7,
        lineHeight: CGFloat = 16,
        paragraphSpacing: CGFloat = 6,
        padding: CGFloat = 8
    ) -> (TimelineRow, CGFloat) -> CGFloat {
        { _, width in
            var height: CGFloat = 0
            for characters in paragraphs {
                let lines = max(1, (CGFloat(characters) * glyphWidth / width).rounded(.up))
                height += lines * lineHeight
            }
            height += CGFloat(max(0, paragraphs.count - 1)) * paragraphSpacing
            return height + padding
        }
    }

    /// A media row: intrinsic image size scaled down to the available width,
    /// height clamped to a maximum.
    private static func mediaMeasurer(
        intrinsicSize: CGSize,
        maximumHeight: CGFloat = 520,
        padding: CGFloat = 8
    ) -> (TimelineRow, CGFloat) -> CGFloat {
        { _, width in
            let renderedWidth = min(intrinsicSize.width, width)
            let aspectRatio = intrinsicSize.width / intrinsicSize.height
            let height = min(renderedWidth / aspectRatio, maximumHeight)
            return height + padding
        }
    }

    private static func messageRow(id: String = "m1") -> TimelineRow {
        .message(uniqueId: id, event: MockEventTimelineItem(), kind: .text, hasReactions: false)
    }

    // MARK: - Measurement math

    @Test
    func oneLineBodyHeightIsWidthIndependent() {
        let row = Self.messageRow()
        let measure = Self.oneLineMeasurer()

        let narrow = TimelineRowMeasurement.height(of: row, width: 320, measuredBy: measure)
        let wide = TimelineRowMeasurement.height(of: row, width: 1200, measuredBy: measure)

        #expect(narrow == 24)
        #expect(wide == 24)
    }

    @Test
    func multiParagraphBodyGrowsAsWidthShrinks() {
        let row = Self.messageRow()
        // Three paragraphs of 40, 80, and 10 characters at 7pt per glyph.
        let measure = Self.paragraphMeasurer(paragraphs: [40, 80, 10])

        // 700pt: 40*7=280 (1 line), 80*7=560 (1 line), 10*7=70 (1 line).
        let wide = TimelineRowMeasurement.height(of: row, width: 700, measuredBy: measure)
        #expect(wide == CGFloat(3 * 16 + 2 * 6 + 8))

        // 300pt: 280 (1 line), 560 (2 lines), 70 (1 line).
        let medium = TimelineRowMeasurement.height(of: row, width: 300, measuredBy: measure)
        #expect(medium == CGFloat(4 * 16 + 2 * 6 + 8))

        // 100pt: 280 (3 lines), 560 (6 lines), 70 (1 line).
        let narrow = TimelineRowMeasurement.height(of: row, width: 100, measuredBy: measure)
        #expect(narrow == CGFloat(10 * 16 + 2 * 6 + 8))

        #expect(wide < medium)
        #expect(medium < narrow)
    }

    @Test
    func mediaRowScalesWithWidthUntilIntrinsicSize() {
        let row = Self.messageRow()
        let measure = Self.mediaMeasurer(intrinsicSize: CGSize(width: 400, height: 300))

        // Narrower than the image: scaled down preserving 4:3.
        let narrow = TimelineRowMeasurement.height(of: row, width: 200, measuredBy: measure)
        #expect(narrow == CGFloat(150 + 8))

        // Wider than the image: rendered at intrinsic size.
        let wide = TimelineRowMeasurement.height(of: row, width: 800, measuredBy: measure)
        #expect(wide == CGFloat(300 + 8))
    }

    @Test
    func mediaRowHeightIsClampedToMaximum() {
        let row = Self.messageRow()
        // A tall portrait image whose unclamped height would be 1600.
        let measure = Self.mediaMeasurer(intrinsicSize: CGSize(width: 200, height: 1600), maximumHeight: 520)

        let height = TimelineRowMeasurement.height(of: row, width: 400, measuredBy: measure)
        #expect(height == CGFloat(520 + 8))
    }

    @Test
    func normalizedHeightClampsDegenerateValues() {
        #expect(TimelineRowMeasurement.normalizedHeight(0) == 1)
        #expect(TimelineRowMeasurement.normalizedHeight(-5) == 1)
        #expect(TimelineRowMeasurement.normalizedHeight(.nan) == 1)
        #expect(TimelineRowMeasurement.normalizedHeight(.infinity) == 1)
        #expect(TimelineRowMeasurement.normalizedHeight(0.5) == 1)
        #expect(TimelineRowMeasurement.normalizedHeight(42.25) == 42.25)
    }

    @Test
    func measurementClampsWidthToAtLeastOne() {
        let row = Self.messageRow()
        var seenWidth: CGFloat = -1
        _ = TimelineRowMeasurement.height(of: row, width: 0) { _, width in
            seenWidth = width
            return 10
        }
        #expect(seenWidth == 1)
    }

    // MARK: - Cache behavior

    @Test
    func repeatLookupHitsWithoutRemeasuring() {
        var cache = TimelineRowHeightCache<Int>()
        let row = Self.messageRow()
        var measureCount = 0
        let measure: (TimelineRow, CGFloat) -> CGFloat = { _, _ in
            measureCount += 1
            return 24
        }

        let first = cache.height(for: row, width: 500, tokens: 13, revision: 0, measure: measure)
        let second = cache.height(for: row, width: 500, tokens: 13, revision: 0, measure: measure)

        #expect(first == 24)
        #expect(second == 24)
        #expect(measureCount == 1)
        #expect(cache.stats == .init(hits: 1, misses: 1))
    }

    @Test
    func widthChangeMissesAndRemeasures() {
        var cache = TimelineRowHeightCache<Int>()
        let row = Self.messageRow()
        let measure = Self.paragraphMeasurer(paragraphs: [80])

        let wide = cache.height(for: row, width: 700, tokens: 13, revision: 0, measure: measure)
        let narrow = cache.height(for: row, width: 300, tokens: 13, revision: 0, measure: measure)

        #expect(wide != narrow)
        #expect(cache.stats == .init(hits: 0, misses: 2))
    }

    @Test
    func tokenSetChangeMissesAndRemeasures() {
        var cache = TimelineRowHeightCache<Int>()
        let row = Self.messageRow()

        let small = cache.height(for: row, width: 500, tokens: 13, revision: 0) { _, _ in 24 }
        let large = cache.height(for: row, width: 500, tokens: 17, revision: 0) { _, _ in 30 }

        #expect(small == 24)
        #expect(large == 30)
        #expect(cache.stats == .init(hits: 0, misses: 2))
    }

    @Test
    func revisionBumpInvalidatesCachedHeight() {
        var cache = TimelineRowHeightCache<Int>()
        let row = Self.messageRow()

        let before = cache.height(for: row, width: 500, tokens: 13, revision: 0) { _, _ in 24 }
        // Content mutated (an edit grew the body): same id, width, and tokens.
        let after = cache.height(for: row, width: 500, tokens: 13, revision: 1) { _, _ in 56 }
        let repeated = cache.height(for: row, width: 500, tokens: 13, revision: 1) { _, _ in
            Issue.record("must not re-measure an unchanged revision")
            return 0
        }

        #expect(before == 24)
        #expect(after == 56)
        #expect(repeated == 56)
        #expect(cache.stats == .init(hits: 1, misses: 2))
    }

    @Test
    func unchangedRevisionHitsAcrossContentOnlyUpdates() {
        var cache = TimelineRowHeightCache<Int>()
        let rows = (0 ..< 50).map { Self.messageRow(id: "m\($0)") }
        for row in rows {
            _ = cache.height(for: row, width: 500, tokens: 13, revision: 0) { _, _ in 24 }
        }
        cache.resetStats()

        // A content-only update (a receipt moved) leaves every revision alone:
        // the whole pass must be hits, with zero re-measures.
        for row in rows {
            _ = cache.height(for: row, width: 500, tokens: 13, revision: 0) { _, _ in
                Issue.record("re-measure storm on a content-only update")
                return 0
            }
        }
        #expect(cache.stats == .init(hits: 50, misses: 0))
    }

    @Test
    func explicitInvalidationDropsOneRow() {
        var cache = TimelineRowHeightCache<Int>()
        let row = Self.messageRow()

        _ = cache.height(for: row, width: 500, tokens: 13, revision: 0) { _, _ in 24 }
        #expect(cache.cachedHeight(forRowId: row.uniqueId) == 24)

        cache.invalidate(rowId: row.uniqueId)
        #expect(cache.cachedHeight(forRowId: row.uniqueId) == nil)

        let remeasured = cache.height(for: row, width: 500, tokens: 13, revision: 0) { _, _ in 32 }
        #expect(remeasured == 32)
    }

    @Test
    func retainPrunesRemovedRows() {
        var cache = TimelineRowHeightCache<Int>()
        for id in ["a", "b", "c"] {
            _ = cache.height(for: Self.messageRow(id: id), width: 500, tokens: 13, revision: 0) { _, _ in 24 }
        }
        #expect(cache.count == 3)

        cache.retain(rowIds: ["a", "c"])
        #expect(cache.count == 2)
        #expect(cache.cachedHeight(forRowId: "b") == nil)
        #expect(cache.cachedHeight(forRowId: "a") == 24)
    }

    @Test
    func invalidateAllEmptiesTheCache() {
        var cache = TimelineRowHeightCache<Int>()
        for id in ["a", "b"] {
            _ = cache.height(for: Self.messageRow(id: id), width: 500, tokens: 13, revision: 0) { _, _ in 24 }
        }
        cache.invalidateAll()
        #expect(cache.count == 0)
    }

    @Test
    func virtualAndStateRowsCacheIndependentlyOfMessages() {
        var cache = TimelineRowHeightCache<Int>()
        let divider = TimelineRow.virtual(uniqueId: "v1", item: .dateDivider(date: Date(timeIntervalSince1970: 0)))
        let state = TimelineRow.state(uniqueId: "s1", event: MockEventTimelineItem(), name: "joined room")
        let message = Self.messageRow()

        let dividerHeight = cache.height(for: divider, width: 500, tokens: 13, revision: 0) { _, _ in 40 }
        let stateHeight = cache.height(for: state, width: 500, tokens: 13, revision: 0) { _, _ in 20 }
        let messageHeight = cache.height(for: message, width: 500, tokens: 13, revision: 0) { _, _ in 24 }

        #expect(dividerHeight == 40)
        #expect(stateHeight == 20)
        #expect(messageHeight == 24)
        #expect(cache.count == 3)
        #expect(cache.cachedHeight(forRowId: "v1") == 40)
        #expect(cache.cachedHeight(forRowId: "s1") == 20)
    }

    @Test
    func cachedHeightsAreNormalized() {
        var cache = TimelineRowHeightCache<Int>()
        let row = Self.messageRow()
        let height = cache.height(for: row, width: 500, tokens: 13, revision: 0) { _, _ in 0 }
        #expect(height == 1)
        #expect(cache.cachedHeight(forRowId: row.uniqueId) == 1)
    }
}

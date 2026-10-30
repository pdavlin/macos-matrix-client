import CoreGraphics
import Testing
@testable import Utils

/// MATRIX-85: the stacked geometry the iOS layout reads, and the anchor
/// compensation it feeds into `ScrollAnchorMath`.
struct TimelineStackGeometryTests {
    @Test func offsetsArePrefixSums() {
        let geometry = TimelineStackGeometry(heights: [10, 20, 30])

        #expect(geometry.offsets == [0, 10, 30])
        #expect(geometry.contentHeight == 60)
        #expect(geometry.minY(ofRow: 2) == 30)
        #expect(geometry.minY(ofRow: 3) == nil)
    }

    @Test func emptyGeometryShowsNothing() {
        let geometry = TimelineStackGeometry(heights: [])

        #expect(geometry.contentHeight == 0)
        #expect(geometry.rows(intersectingMinY: 0, maxY: 100).isEmpty)
        #expect(geometry.anchorRow(viewportMinY: 0, viewportMaxY: 100) == nil)
    }

    @Test func intersectingRowsIncludePartialRowsAtBothEnds() {
        let geometry = TimelineStackGeometry(heights: [10, 20, 30, 40])

        // 15...45 cuts row 1 (10..<30) and row 2 (30..<60).
        #expect(geometry.rows(intersectingMinY: 15, maxY: 45) == 1 ..< 3)
    }

    @Test func rowStartingExactlyAtTheSpanEndIsNotIncluded() {
        let geometry = TimelineStackGeometry(heights: [10, 20, 30])

        #expect(geometry.rows(intersectingMinY: 0, maxY: 30) == 0 ..< 2)
    }

    @Test func spanBeyondTheContentIsEmpty() {
        let geometry = TimelineStackGeometry(heights: [10, 20])

        #expect(geometry.rows(intersectingMinY: 30, maxY: 90).isEmpty)
        #expect(geometry.rows(intersectingMinY: -50, maxY: 0).isEmpty)
    }

    @Test func spanStartingBeforeTheOriginClampsToRowZero() {
        // A rubber-band bounce past the newest end reports a negative origin.
        let geometry = TimelineStackGeometry(heights: [10, 20])

        #expect(geometry.rows(intersectingMinY: -20, maxY: 15) == 0 ..< 2)
    }

    @Test func anchorIsTheVisibleRowFarthestFromTheOrigin() {
        let geometry = TimelineStackGeometry(heights: [50, 50, 50, 50, 50])

        #expect(geometry.anchorRow(viewportMinY: 60, viewportMaxY: 160) == 3)
    }

    @Test func manyRowsStillResolveTheRightRange() {
        let geometry = TimelineStackGeometry(heights: Array(repeating: 37, count: 10000))

        let rows = geometry.rows(intersectingMinY: 37 * 5000 + 1, maxY: 37 * 5010)

        #expect(rows == 5000 ..< 5010)
    }

    // MARK: - Compensation through the geometry

    @Test func newestEndInsertWhileScrolledUpHoldsTheAnchorStill() {
        // The reader is scrolled up; two new messages (80pt) arrive at the
        // newest end, which is the document origin. Every row moves 80pt away
        // from the origin, so the viewport must follow by exactly 80pt.
        let before = TimelineStackGeometry(heights: [40, 40, 40, 40, 40, 40])
        let viewport: (minY: CGFloat, height: CGFloat) = (100, 100)
        let anchor = before.anchorRow(viewportMinY: viewport.minY, viewportMaxY: viewport.minY + viewport.height)
        #expect(anchor == 4)

        let after = TimelineStackGeometry(heights: [50, 30] + before.heights)
        let anchorAfter = 4 + 2

        let origin = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: viewport.minY,
            anchorOriginBefore: before.minY(ofRow: 4) ?? 0,
            anchorOriginAfter: after.minY(ofRow: anchorAfter) ?? 0,
            maximumOriginY: ScrollAnchorMath.maximumOriginY(
                documentHeight: after.contentHeight,
                viewportHeight: viewport.height
            )
        )

        #expect(origin == 180)
    }

    @Test func backPaginationLeavesTheViewportAlone() {
        // Older rows append at the far end of the document, so the anchor's
        // distance from the origin does not change and no compensation runs.
        let before = TimelineStackGeometry(heights: [40, 40, 40, 40])
        let after = TimelineStackGeometry(heights: before.heights + Array(repeating: 25, count: 30))

        #expect(before.minY(ofRow: 3) == after.minY(ofRow: 3))
    }

    @Test func heightChangeNewerThanTheAnchorMovesTheViewportByTheDelta() {
        // A reaction strip appears on row 1 (below the viewport): +22pt.
        let before = TimelineStackGeometry(heights: [40, 40, 40, 40, 40, 40])
        var heights = before.heights
        heights[1] += 22
        let after = TimelineStackGeometry(heights: heights)

        let origin = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: 120,
            anchorOriginBefore: before.minY(ofRow: 5) ?? 0,
            anchorOriginAfter: after.minY(ofRow: 5) ?? 0,
            maximumOriginY: ScrollAnchorMath.maximumOriginY(documentHeight: after.contentHeight, viewportHeight: 100)
        )

        #expect(origin == 142)
    }

    // MARK: - Scroll metrics

    @Test func bottomThresholdMatchesTheMacContainer() {
        #expect(TimelineScrollMetrics.isAtBottom(originY: 0))
        #expect(TimelineScrollMetrics.isAtBottom(originY: 40))
        #expect(!TimelineScrollMetrics.isAtBottom(originY: 41))
    }

    @Test func paginationStartsWithin200PointsOfTheOldestEnd() {
        #expect(!TimelineScrollMetrics.shouldPaginate(originY: 0, documentHeight: 1000, viewportHeight: 500))
        #expect(TimelineScrollMetrics.shouldPaginate(originY: 300, documentHeight: 1000, viewportHeight: 500))
        #expect(!TimelineScrollMetrics.shouldPaginate(originY: 299, documentHeight: 1000, viewportHeight: 500))
    }

    @Test func shortTimelineAlwaysAsksForMore() {
        #expect(TimelineScrollMetrics.shouldPaginate(originY: 0, documentHeight: 120, viewportHeight: 700))
    }
}

import CoreGraphics
import Testing
@testable import TimelineSpikeApp

@Suite("Scroll anchor maths")
struct ScrollAnchorMathTests {
    @Test("A prepend moves the viewport down by exactly the distance the anchor row moved")
    func prependFollowsTheAnchor() {
        // 50 events worth 1680pt were inserted above, so the anchor row's top moved from
        // 12000 to 13680 in the document, and the viewport follows it.
        let origin = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: 4200,
            anchorTopBefore: 12000,
            anchorTopAfter: 13680,
            maximumOriginY: 20000
        )
        #expect(origin == 5880)
    }

    @Test("A prepend while pinned to the top still moves, because the top moved")
    func prependFromTheTop() {
        let origin = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: 0,
            anchorTopBefore: 0,
            anchorTopAfter: 1680,
            maximumOriginY: 20000
        )
        #expect(origin == 1680)
    }

    @Test("An anchor that did not move leaves the viewport alone")
    func stillAnchorDoesNotMove() {
        let origin = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: 4200,
            anchorTopBefore: 12000,
            anchorTopAfter: 12000,
            maximumOriginY: 20000
        )
        #expect(origin == 4200)
    }

    @Test("An anchor that moved up pulls the viewport up with it")
    func shrinkingAboveTheAnchor() {
        let origin = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: 4200,
            anchorTopBefore: 12000,
            anchorTopAfter: 11976,
            maximumOriginY: 20000
        )
        #expect(origin == 4176)
    }

    @Test("The compensating move is clamped to the taller document, never past it")
    func prependClampsToTheDocument() {
        let origin = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: 900,
            anchorTopBefore: 900,
            anchorTopAfter: 2580,
            maximumOriginY: 2000
        )
        #expect(origin == 2000)
    }

    @Test("The maximum origin is the document less the viewport, and never negative")
    func maximumOrigin() {
        #expect(ScrollAnchorMath.maximumOriginY(documentHeight: 5000, viewportHeight: 860) == 4140)
        #expect(ScrollAnchorMath.maximumOriginY(documentHeight: 400, viewportHeight: 860) == 0)
    }

    @Test("Clamping keeps the origin inside the document")
    func clamping() {
        #expect(ScrollAnchorMath.clamped(-30, maximumOriginY: 900) == 0)
        #expect(ScrollAnchorMath.clamped(1200, maximumOriginY: 900) == 900)
        #expect(ScrollAnchorMath.clamped(300, maximumOriginY: 900) == 300)
        #expect(ScrollAnchorMath.clamped(300, maximumOriginY: -10) == 0)
    }

    @Test("Only rows above the anchor row are compensated for")
    func compensationCountsRowsAboveTheAnchor() {
        let changes = [
            RowHeightCache.HeightChange(row: 10, delta: 18),
            RowHeightCache.HeightChange(row: 99, delta: 40),
            RowHeightCache.HeightChange(row: 100, delta: 200),
            RowHeightCache.HeightChange(row: 140, delta: -60)
        ]
        #expect(ScrollAnchorMath.compensation(for: changes, anchorRow: 100) == 58)
    }

    @Test("A row above the viewport that shrinks pulls the viewport back up")
    func compensationHandlesShrinking() {
        let changes = [RowHeightCache.HeightChange(row: 3, delta: -24)]
        #expect(ScrollAnchorMath.compensation(for: changes, anchorRow: 50) == -24)
    }

    @Test("On-screen changes are not compensated for; the message really did grow")
    func onScreenChangesAreNotCompensated() {
        let changes = [
            RowHeightCache.HeightChange(row: 50, delta: 32),
            RowHeightCache.HeightChange(row: 51, delta: 32)
        ]
        #expect(ScrollAnchorMath.compensation(for: changes, anchorRow: 50) == 0)
    }

    @Test("Nothing changed above the anchor means the viewport does not move")
    func emptyCompensation() {
        #expect(ScrollAnchorMath.compensation(for: [], anchorRow: 12) == 0)
    }
}

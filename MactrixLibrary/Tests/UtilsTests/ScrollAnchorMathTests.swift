import CoreGraphics
import Testing
@testable import Utils

struct ScrollAnchorMathTests {
    @Test func prependMovesTheViewportByTheDistanceTheAnchorMoved() {
        // A batch worth 1680pt landed between the document origin and the anchor row, so
        // the row's distance from the origin grew by that much and the viewport follows it.
        let origin = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: 4200,
            anchorOriginBefore: 12000,
            anchorOriginAfter: 13680,
            maximumOriginY: 20000
        )

        #expect(origin == 5880)
    }

    @Test func anchorAtTheDocumentOriginStillMoves() {
        let origin = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: 0,
            anchorOriginBefore: 0,
            anchorOriginAfter: 1680,
            maximumOriginY: 20000
        )

        #expect(origin == 1680)
    }

    @Test func anchorThatDidNotMoveLeavesTheViewportAlone() {
        // The unflipped timeline measures rows from the newest end, so a pure
        // back-pagination batch lands beyond every visible row and moves none of them.
        let origin = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: 4200,
            anchorOriginBefore: 12000,
            anchorOriginAfter: 12000,
            maximumOriginY: 20000
        )

        #expect(origin == 4200)
    }

    @Test func anchorThatMovedTowardTheOriginPullsTheViewportWithIt() {
        let origin = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: 4200,
            anchorOriginBefore: 12000,
            anchorOriginAfter: 11976,
            maximumOriginY: 20000
        )

        #expect(origin == 4176)
    }

    @Test func compensatingMoveIsClampedToTheDocument() {
        let origin = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: 900,
            anchorOriginBefore: 900,
            anchorOriginAfter: 2580,
            maximumOriginY: 2000
        )

        #expect(origin == 2000)
    }

    @Test func compensatingMoveNeverGoesNegative() {
        let origin = ScrollAnchorMath.originRestoringAnchor(
            currentOriginY: 100,
            anchorOriginBefore: 900,
            anchorOriginAfter: 0,
            maximumOriginY: 2000
        )

        #expect(origin == 0)
    }

    @Test func maximumOriginIsTheDocumentLessTheViewport() {
        #expect(ScrollAnchorMath.maximumOriginY(documentHeight: 5000, viewportHeight: 860) == 4140)
        #expect(ScrollAnchorMath.maximumOriginY(documentHeight: 400, viewportHeight: 860) == 0)
    }

    @Test func clampingKeepsTheOriginInsideTheDocument() {
        #expect(ScrollAnchorMath.clamped(-30, maximumOriginY: 900) == 0)
        #expect(ScrollAnchorMath.clamped(1200, maximumOriginY: 900) == 900)
        #expect(ScrollAnchorMath.clamped(300, maximumOriginY: 900) == 300)
        #expect(ScrollAnchorMath.clamped(300, maximumOriginY: -10) == 0)
    }
}

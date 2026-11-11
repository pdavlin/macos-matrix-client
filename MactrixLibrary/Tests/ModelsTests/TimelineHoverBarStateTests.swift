import Models
import Testing

/// MATRIX-145: which message row the floating hover bar shows for.
struct TimelineHoverBarStateTests {
    private typealias State = TimelineHoverBarState<String>

    @Test func startsHidden() {
        let state = State()
        #expect(state.shownRow == nil)
        #expect(state.hoveredRow == nil)
        #expect(!state.isScrolling)
        #expect(state.suppressions.isEmpty)
    }

    @Test func showsForTheMessageRowUnderThePointer() {
        var state = State()
        let changed = state.apply(.pointerOverRow("a"))
        #expect(changed)
        #expect(state.shownRow == "a")
    }

    @Test func movesToTheNextMessageRow() {
        var state = State()
        state.apply(.pointerOverRow("a"))
        let changed = state.apply(.pointerOverRow("b"))
        #expect(changed)
        #expect(state.shownRow == "b")
    }

    @Test func theSameRowAgainIsNoChange() {
        var state = State()
        state.apply(.pointerOverRow("a"))
        let changed = state.apply(.pointerOverRow("a"))
        #expect(!changed)
        #expect(state.shownRow == "a")
    }

    @Test func aRowWithoutABarHidesIt() {
        var state = State()
        state.apply(.pointerOverRow("a"))
        let changed = state.apply(.pointerOverRow(nil))
        #expect(changed)
        #expect(state.shownRow == nil)
    }

    @Test func theBarStaysWhileThePointerIsOverIt() {
        var state = State()
        state.apply(.pointerOverRow("a"))
        let changed = state.apply(.pointerOverBar)
        #expect(!changed)
        #expect(state.shownRow == "a")
    }

    @Test func leavingTheTimelineHidesTheBar() {
        var state = State()
        state.apply(.pointerOverRow("a"))
        let changed = state.apply(.pointerExited)
        #expect(changed)
        #expect(state.shownRow == nil)
        #expect(state.hoveredRow == nil)
    }

    @Test func aScrollHidesTheBarUntilThePointerIsReportedAgain() {
        var state = State()
        state.apply(.pointerOverRow("a"))
        let changed = state.apply(.scrollBegan)
        #expect(changed)
        #expect(state.shownRow == nil)

        // The row under a still pointer is not known when the scroll stops.
        let changedAgain = state.apply(.scrollEnded)
        #expect(!changedAgain)
        #expect(state.shownRow == nil)

        // The controller reports the pointer once the scroll stops.
        let changedThird = state.apply(.pointerOverRow("c"))
        #expect(changedThird)
        #expect(state.shownRow == "c")
    }

    @Test func pointerMovesDuringAScrollShowWhenItStops() {
        var state = State()
        state.apply(.scrollBegan)
        let changed = state.apply(.pointerOverRow("b"))
        #expect(!changed)
        #expect(state.shownRow == nil)
        #expect(state.hoveredRow == "b")
        let changedAgain = state.apply(.scrollEnded)
        #expect(changedAgain)
        #expect(state.shownRow == "b")
    }

    @Test func aSheetHidesTheBarAndItComesBackWhenTheSheetCloses() {
        var state = State()
        state.apply(.pointerOverRow("a"))
        let changed = state.apply(.suppress(.sheet))
        #expect(changed)
        #expect(state.shownRow == nil)
        let changedAgain = state.apply(.unsuppress(.sheet))
        #expect(changedAgain)
        #expect(state.shownRow == "a")
    }

    @Test func theBarStaysHiddenWhileAnySuppressionIsOpen() {
        var state = State()
        state.apply(.pointerOverRow("a"))
        state.apply(.suppress(.sheet))
        state.apply(.suppress(.reactionPicker))
        let changed = state.apply(.unsuppress(.sheet))
        #expect(!changed)
        #expect(state.shownRow == nil)
        let changedAgain = state.apply(.unsuppress(.reactionPicker))
        #expect(changedAgain)
        #expect(state.shownRow == "a")
    }

    @Test func pointerMovesWhileSuppressedAreKept() {
        var state = State()
        state.apply(.suppress(.reactionPicker))
        let changed = state.apply(.pointerOverRow("b"))
        #expect(!changed)
        let changedAgain = state.apply(.unsuppress(.reactionPicker))
        #expect(changedAgain)
        #expect(state.shownRow == "b")
    }

    @Test func aRemovedRowLosesTheBar() {
        var state = State()
        state.apply(.pointerOverRow("a"))
        let changed = state.apply(.rowRemoved("b"))
        #expect(!changed)
        #expect(state.shownRow == "a")
        let changedAgain = state.apply(.rowRemoved("a"))
        #expect(changedAgain)
        #expect(state.shownRow == nil)
    }

    @Test func unsuppressingWhatIsNotSuppressedIsNoChange() {
        var state = State()
        state.apply(.pointerOverRow("a"))
        let changed = state.apply(.unsuppress(.sheet))
        #expect(!changed)
        #expect(state.shownRow == "a")
    }
}

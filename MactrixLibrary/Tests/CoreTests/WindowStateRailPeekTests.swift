@testable import Core
import Models
import Testing

/// MATRIX-227: a Go-menu key selects a rail item and peeks its name; a
/// click on the rail selects it with no name and collapses a name that
/// shows.
@MainActor
struct WindowStateRailPeekTests {
    @Test
    func aGoMenuKeySelectsTheItemAndPeeksItsName() {
        let state = WindowState()
        let now = ContinuousClock.now
        state.selectRailItemFromGoMenu(.label("work"), now: now)
        #expect(state.railFilter == .label("work"))
        #expect(state.railNamePeek.item(at: now)?.filter == .label("work"))
    }

    @Test
    func aClickSelectsTheItemWithNoName() {
        let state = WindowState()
        state.selectRailItemByClick(.space("!dev"))
        #expect(state.railFilter == .space("!dev"))
        #expect(state.railNamePeek.item == nil)
    }

    @Test
    func aClickCollapsesANameThatShows() {
        let state = WindowState()
        state.selectRailItemFromGoMenu(.label("work"))
        state.selectRailItemByClick(.inbox)
        #expect(state.railFilter == .inbox)
        #expect(state.railNamePeek.item == nil)
    }
}

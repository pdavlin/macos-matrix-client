import Models
import Testing

/// MATRIX-227: the rail name peek's timing. The state machine takes the
/// time with each change, so these tests run on made-up instants and never
/// wait.
struct RailNamePeekTests {
    /// Any start time: the machine only compares instants.
    private let start = ContinuousClock.now

    private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start + .milliseconds(milliseconds)
    }

    @Test
    func showsNothingAtFirst() {
        let peek = RailNamePeek()
        #expect(peek.item == nil)
        #expect(peek.item(at: at(0)) == nil)
    }

    /// The name shows for one second from the key, then not.
    @Test
    func aKeyShowsTheNameForOneSecond() {
        var peek = RailNamePeek()
        peek.show(.label("work"), at: at(0))
        #expect(RailNamePeek.duration == .seconds(1))
        #expect(peek.item(at: at(0))?.filter == .label("work"))
        #expect(peek.item(at: at(999)) != nil)
        #expect(peek.item(at: at(1000)) == nil)
        #expect(peek.item?.hidesAt == at(1000))
    }

    @Test
    func expireCollapsesOnlyWhenTheTimeIsOver() {
        var peek = RailNamePeek()
        peek.show(.inbox, at: at(0))
        peek.expire(at: at(500))
        #expect(peek.item != nil)
        peek.expire(at: at(1000))
        #expect(peek.item == nil)
    }

    /// A new key during the peek replaces the name and starts the second
    /// again, so the old time does not collapse the new name.
    @Test
    func aNewKeyReplacesTheNameAndRestartsTheTime() throws {
        var peek = RailNamePeek()
        peek.show(.label("work"), at: at(0))
        let first = try #require(peek.item)
        peek.show(.space("!dev"), at: at(600))
        let second = try #require(peek.item)
        #expect(second.filter == .space("!dev"))
        #expect(second.id != first.id)
        #expect(second.hidesAt == at(1600))
        peek.expire(at: at(1000))
        #expect(peek.item == second)
        peek.expire(at: at(1600))
        #expect(peek.item == nil)
    }

    /// The same key again is a new peek too: a new ID, so the view shows it
    /// again, and a new time.
    @Test
    func theSameKeyAgainRestartsTheTime() throws {
        var peek = RailNamePeek()
        peek.show(.inbox, at: at(0))
        let first = try #require(peek.item)
        peek.show(.inbox, at: at(900))
        let again = try #require(peek.item)
        #expect(again.id != first.id)
        #expect(peek.item(at: at(1500)) == again)
    }

    /// A click on the rail collapses the name at once.
    @Test
    func hideCollapsesAtOnce() {
        var peek = RailNamePeek()
        peek.show(.label("work"), at: at(0))
        peek.hide()
        #expect(peek.item == nil)
        #expect(peek.item(at: at(100)) == nil)
    }
}

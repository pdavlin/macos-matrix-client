import Foundation
import Testing
@testable import Utils

/// MATRIX-166 follow-up: the Mac app shortens the wait before a tooltip.
struct ToolTipDelayTests {
    @Test func registersAShortDelayUnderTheAppKitKey() {
        let delay = ToolTipDelay.registeredDefaults["NSInitialToolTipDelay"]
        #expect(delay.map { (100 ... 1000).contains($0) } == true)
    }

    @Test func aValueTheUserSetWins() throws {
        let suite = "ToolTipDelayTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        ToolTipDelay.register(in: defaults)
        #expect(defaults.integer(forKey: ToolTipDelay.defaultsKey) == ToolTipDelay.initialMilliseconds)

        defaults.set(150, forKey: ToolTipDelay.defaultsKey)
        ToolTipDelay.register(in: defaults)
        #expect(defaults.integer(forKey: ToolTipDelay.defaultsKey) == 150)
    }
}

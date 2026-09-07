@testable import Models
import Testing

/// S-35: the shared UTD cause. `UtdReporter` logs `logLabel` and the timeline
/// row shows `displayText`, so both surfaces read one mapping.
struct UnableToDecryptCauseTests {
    @Test
    func logLabelsAreUniqueAndGreppable() {
        let labels = UnableToDecryptCause.allCases.map(\.logLabel)

        #expect(Set(labels).count == UnableToDecryptCause.allCases.count)
        #expect(labels.allSatisfy { !$0.isEmpty })
        // The log predicate in `UtdReporter` matches on these exact strings.
        #expect(UnableToDecryptCause.unknown.logLabel == "unknown")
        #expect(UnableToDecryptCause.sentBeforeWeJoined.logLabel == "sent-before-we-joined")
        #expect(UnableToDecryptCause.withheldBySender.logLabel == "withheld-by-sender")
    }

    /// `.unknown` means the SDK assigned no cause. The row must state the
    /// failure and claim nothing about why, so it carries no reason text.
    @Test
    func onlyUnknownHasNoDisplayText() {
        #expect(UnableToDecryptCause.unknown.displayText == nil)

        let attributed = UnableToDecryptCause.allCases.filter { $0 != .unknown }
        #expect(attributed.allSatisfy { $0.displayText?.isEmpty == false })
    }
}

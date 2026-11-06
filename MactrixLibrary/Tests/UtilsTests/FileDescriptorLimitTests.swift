import Darwin
import Testing
@testable import Utils

/// MATRIX-122: the app raises its open-file soft limit from macOS's 256.
struct FileDescriptorLimitTests {
    @Test func raisesTheDefaultSoftLimit() {
        #expect(FileDescriptorLimit.target(currentSoft: 256, hard: rlim_t.max) == 4096)
    }

    @Test func neverGoesAboveTheHardLimit() {
        #expect(FileDescriptorLimit.target(currentSoft: 256, hard: 1024) == 1024)
    }

    @Test func neverLowersAHigherSoftLimit() {
        #expect(FileDescriptorLimit.target(currentSoft: 10240, hard: rlim_t.max) == 10240)
    }

    @Test func raisingTheLiveLimitKeepsItAtLeastTheDesiredValue() throws {
        let result = try #require(FileDescriptorLimit.raiseSoftLimit())
        #expect(result.after >= result.before)
    }
}

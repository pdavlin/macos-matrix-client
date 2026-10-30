import Testing
@testable import Utils

/// MATRIX-96: the SDK cross-process lock configuration of each process.
struct CrossProcessLockChoiceTests {
    @Test func macAppKeepsTheSDKDefault() {
        #expect(CrossProcessLockChoice.choice(for: .app, on: .macOS) == .sdkDefault)
    }

    @Test func macNeverTakesALock() {
        #expect(CrossProcessLockChoice.choice(for: .notificationServiceExtension, on: .macOS) == .sdkDefault)
    }

    @Test func iOSAppIsMultiProcessWithTheAppHolder() {
        #expect(CrossProcessLockChoice.choice(for: .app, on: .iOS) == .multiProcess(holderName: "app"))
    }

    @Test func notificationServiceExtensionIsMultiProcessWithItsOwnHolder() {
        #expect(CrossProcessLockChoice.choice(for: .notificationServiceExtension, on: .iOS) == .multiProcess(holderName: "nse"))
    }

    /// The SDK requires a different holder name in each process.
    @Test func theTwoIOSProcessesHaveDifferentHolders() {
        #expect(CrossProcessLockChoice.choice(for: .app, on: .iOS)
            != CrossProcessLockChoice.choice(for: .notificationServiceExtension, on: .iOS))
    }

    /// The FFI `Client` refuses a multi-process configuration without a session delegate.
    @Test func onlyMultiProcessRequiresASessionDelegate() {
        #expect(CrossProcessLockChoice.sdkDefault.requiresSessionDelegate == false)
        #expect(CrossProcessLockChoice.multiProcess(holderName: "app").requiresSessionDelegate)
    }

    @Test func currentPlatformMatchesTheBuildPlatform() {
        #if os(iOS)
            #expect(ClientPlatform.current == .iOS)
        #else
            #expect(ClientPlatform.current == .macOS)
            #expect(CrossProcessLockChoice.choice(for: .app) == .sdkDefault)
        #endif
    }
}

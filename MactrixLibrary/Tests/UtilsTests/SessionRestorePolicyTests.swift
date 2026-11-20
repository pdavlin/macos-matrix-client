import Testing
@testable import Utils

/// MATRIX-213: an XCTest host restores no saved session unless the test
/// injected the dev account.
struct SessionRestorePolicyTests {
    private static let devUser = "@dev:davlin.io"
    private static let otherUser = "@someone:davlin.io"

    @Test func theAppRestoresAnySession() {
        let policy = SessionRestorePolicy(environment: ["HOME": "/Users/test"])
        #expect(policy == .anySession)
        #expect(policy.allowsRestore(of: Self.otherUser))
    }

    /// The dev account in the environment of the app changes nothing: only a
    /// test host is limited.
    @Test func devCredentialsOutsideATestHostChangeNothing() {
        #expect(SessionRestorePolicy(environment: ["MATRIX_DEV_USER": Self.devUser]) == .anySession)
    }

    @Test(arguments: SessionRestorePolicy.testHostEnvironmentKeys)
    func eachTestHostKeyMarksATestHost(key: String) {
        #expect(SessionRestorePolicy.isTestHost(environment: [key: "/tmp/x"]))
        #expect(SessionRestorePolicy(environment: [key: "/tmp/x"]) == .noSession)
    }

    @Test func aTestHostWithoutDevCredentialsRestoresNothing() {
        let policy = SessionRestorePolicy(environment: ["XCTestConfigurationFilePath": "/tmp/x"])
        #expect(policy == .noSession)
        #expect(!policy.allowsRestore(of: Self.devUser))
        #expect(!policy.allowsRestore(of: Self.otherUser))
    }

    @Test func anEmptyDevUserIsNoCredential() {
        let environment = ["XCTestBundlePath": "/tmp/x", "MATRIX_DEV_USER": ""]
        #expect(SessionRestorePolicy(environment: environment) == .noSession)
    }

    @Test func aTestHostWithDevCredentialsRestoresOnlyTheDevAccount() {
        let environment = ["XCTestSessionIdentifier": "1", "MATRIX_DEV_USER": Self.devUser]
        let policy = SessionRestorePolicy(environment: environment)
        #expect(policy == .onlyUser(Self.devUser))
        #expect(policy.allowsRestore(of: Self.devUser))
        #expect(!policy.allowsRestore(of: Self.otherUser))
    }

    /// The fallback key that the integration tests also read.
    @Test func theTestRunnerPrefixedKeyIsADevCredential() {
        let environment = ["XCTestConfigurationFilePath": "/tmp/x", "TEST_RUNNER_MATRIX_DEV_USER": Self.devUser]
        #expect(SessionRestorePolicy(environment: environment) == .onlyUser(Self.devUser))
    }
}

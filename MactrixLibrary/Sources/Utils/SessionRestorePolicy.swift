import Foundation

/// Which saved session a launch may restore (MATRIX-213).
///
/// The app restores any saved session. An XCTest host restores none unless
/// the test injected the dev account: `MATRIX_DEV_USER` is set, and the saved
/// session is that user. The test host also has its own bundle identifier,
/// so its container and keychain items are not the daily app's. This policy
/// is the second guard, for a host that runs with the daily identity.
public enum SessionRestorePolicy: Equatable, Sendable {
    /// Not an XCTest host: restore the saved session.
    case anySession
    /// An XCTest host with the dev account in its environment: restore only a
    /// session of this user.
    case onlyUser(String)
    /// An XCTest host without dev credentials: restore nothing, and do not
    /// read the keychain.
    case noSession

    /// The environment keys that XCTest sets in a test host process. One of
    /// them is enough.
    static let testHostEnvironmentKeys = [
        "XCTestConfigurationFilePath",
        "XCTestBundlePath",
        "XCTestSessionIdentifier",
        "XCInjectBundleInto",
    ]

    public init(environment: [String: String]) {
        guard Self.isTestHost(environment: environment) else {
            self = .anySession
            return
        }
        // The same keys, in the same order, as the integration tests read.
        let devUser = environment["MATRIX_DEV_USER"] ?? environment["TEST_RUNNER_MATRIX_DEV_USER"]
        guard let devUser, !devUser.isEmpty else {
            self = .noSession
            return
        }
        self = .onlyUser(devUser)
    }

    /// The policy of this process.
    public static var current: SessionRestorePolicy {
        SessionRestorePolicy(environment: ProcessInfo.processInfo.environment)
    }

    /// `true` if `environment` is the environment of an XCTest host.
    public static func isTestHost(environment: [String: String]) -> Bool {
        testHostEnvironmentKeys.contains { environment[$0] != nil }
    }

    /// `true` if the launch may restore a saved session of `userID`.
    public func allowsRestore(of userID: String) -> Bool {
        switch self {
        case .anySession: true
        case let .onlyUser(allowed): userID == allowed
        case .noSession: false
        }
    }
}

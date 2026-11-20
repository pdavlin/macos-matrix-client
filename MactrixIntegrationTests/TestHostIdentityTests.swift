import Core
import Foundation
import Utils
import XCTest

/// MATRIX-213 guard. These tests run inside a Mactrix app host. On 2026-11-19
/// the host had the daily app's bundle identifier, so it shared the daily
/// app's sandbox container and keychain items, and it restored the prod
/// session. The scheme now builds the host in the Test configuration, with
/// its own bundle identifier. These tests fail if the host gets the daily
/// identity again.
final class TestHostIdentityTests: XCTestCase {
    /// The daily app's bundle identifier: also the name of its sandbox
    /// container, its session store folders, and its keychain service.
    private static let dailyIdentifier = "io.davlin.matrixclient"
    /// The test host's bundle identifier (the Test configuration).
    private static let testHostIdentifier = "io.davlin.matrixclient.tests"

    func testHostHasItsOwnBundleIdentifier() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, Self.testHostIdentifier)
    }

    func testSessionStoresAreInTheTestHostContainer() {
        for root in [SessionStorageLocation.roots.data, SessionStorageLocation.roots.caches] {
            let path = root.path(percentEncoded: false)
            XCTAssertFalse(root.pathComponents.contains(Self.dailyIdentifier), path)
            XCTAssertTrue(path.contains("/Library/Containers/\(Self.testHostIdentifier)/"), path)
            XCTAssertEqual(root.lastPathComponent, Self.testHostIdentifier, path)
        }
    }

    func testKeychainServiceIsNotTheDailyApp() {
        let service = AppKeychain().service
        XCTAssertNotEqual(service, Self.dailyIdentifier)
        XCTAssertEqual(service, Self.testHostIdentifier)
    }

    /// The second guard: the host sees the XCTest environment, so the launch
    /// restores no saved session unless the test injected the dev account.
    func testHostRestoresOnlyAnInjectedDevSession() {
        let environment = ProcessInfo.processInfo.environment
        XCTAssertTrue(
            SessionRestorePolicy.isTestHost(environment: environment),
            "the host does not see the XCTest environment, so it would restore any saved session"
        )
        XCTAssertNotEqual(SessionRestorePolicy.current, .anySession)
    }
}

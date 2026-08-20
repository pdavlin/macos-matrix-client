import Foundation
@testable import Mactrix
import MatrixRustSDK
import XCTest

/// Headless network integration test for S-05.
///
/// Exercises the app's own client-construction path
/// (`MatrixClient.clientBuilder` / `MatrixClient.loginDetails`, which builds
/// a `ClientBuilder` via `serverNameOrHomeserverUrl` — the SDK's own
/// `.well-known/matrix/client` discovery, never hand-rolled here) against the
/// live davlin.io homeserver:
///
///   1. Discover davlin.io.
///   2. Login as the dev account with password auth.
///   3. Confirm whoami (the user ID returned by the homeserver) and the
///      discovered homeserver base URL.
///   4. Logout.
///
/// This talks to a real network and a real account, so it is gated behind
/// `MATRIX_DEV_PASSWORD` and skipped otherwise. Only ever run against the
/// dev account (`MATRIX_DEV_USER`) per CLAUDE.md hard rule 3 — never prod.
///
/// This test intentionally calls `login` / `userId` / `logout` directly on
/// the `unauthenticatedClient` returned by `MatrixClient.loginDetails`,
/// rather than going through `HomeserverLogin.loginPassword`. That wrapper's
/// `onSuccessfullLogin` persists the session to the shared app keychain
/// (service = the host app's bundle identifier), which on a machine that
/// also runs the real Mactrix app would clobber whatever session — dev or
/// prod — is already stored there. The lower-level calls used here exercise
/// the same discovery/login/whoami/logout surface without touching the
/// keychain at all.
///
/// Providing credentials:
///   - In Xcode: Product > Scheme > Edit Scheme > Test > Arguments >
///     Environment Variables. Enable and fill in `MATRIX_DEV_USER` /
///     `MATRIX_DEV_PASSWORD` locally — this is saved to your personal
///     `xcuserdata`, which is gitignored and never shared. The shared,
///     checked-in scheme declares both keys disabled with empty values, as
///     documentation only.
///   - Headless (agents/CI): as of this Xcode beta, `xcodebuild test` does
///     not resolve `$(VAR)` references inside a shared scheme's
///     `<EnvironmentVariables>` (they pass through as the literal, unexpanded
///     text), and plain `TEST_RUNNER_`-prefixed command-line overrides are
///     not auto-injected into the test process either — both were tried and
///     both left the test skipped. What does work: run
///     `xcodebuild build-for-testing -scheme MactrixIntegrationTests` once to
///     produce `<DerivedData>/Build/Products/*.xctestrun`, patch that file's
///     `MactrixIntegrationTests:EnvironmentVariables` dictionary in place with
///     `MATRIX_DEV_USER` / `MATRIX_DEV_PASSWORD` via `PlistBuddy -c "Add ..."`,
///     run `xcodebuild test-without-building -xctestrun <path> -destination
///     "platform=macOS,arch=arm64"`, then delete those two keys from the
///     `.xctestrun` again so the secret doesn't linger on disk. This test
///     also accepts `TEST_RUNNER_`-prefixed env var names as a fallback, in
///     case a future Xcode version fixes the auto-injection path.
final class LoginIntegrationTests: XCTestCase {
    private static let deviceName = "s05-integration"
    private static let homeserver = "davlin.io"

    func testDiscoveryAndPasswordLoginAgainstDavlinIO() async throws {
        let env = ProcessInfo.processInfo.environment
        guard
            let devUserId = env["MATRIX_DEV_USER"] ?? env["TEST_RUNNER_MATRIX_DEV_USER"],
            let devPassword = env["MATRIX_DEV_PASSWORD"] ?? env["TEST_RUNNER_MATRIX_DEV_PASSWORD"],
            !devPassword.isEmpty
        else {
            throw XCTSkip("MATRIX_DEV_PASSWORD not set — skipping network integration test.")
        }

        // Build an unauthenticated client against the bare server name.
        // ClientBuilder.serverNameOrHomeserverUrl performs the SDK's native
        // well-known discovery; MatrixClient.loginDetails is the app's own
        // entry point for this (see WelcomeSheetView.loadHomeserver).
        let homeserverLogin = try await MatrixClient.loginDetails(homeServer: Self.homeserver)

        XCTAssertTrue(
            homeserverLogin.loginDetails.supportsPasswordLogin(),
            "davlin.io should advertise password login support after discovery"
        )

        let client = homeserverLogin.unauthenticatedClient

        try await client.login(
            username: devUserId,
            password: devPassword,
            initialDeviceName: Self.deviceName,
            deviceId: nil
        )

        // whoami: the user ID the homeserver returned for this login.
        let loggedInUserId = try client.userId()
        XCTAssertEqual(loggedInUserId, devUserId, "whoami should confirm the dev account")

        // Proof discovery actually resolved via well-known rather than
        // connecting to davlin.io directly: the session's homeserver URL
        // should be the exe.xyz base_url advertised by
        // https://davlin.io/.well-known/matrix/client, not davlin.io itself.
        let session = try client.session()
        XCTAssertTrue(
            session.homeserverUrl.contains("davlin-matrix.exe.xyz"),
            "expected well-known discovery to resolve to the exe.xyz base_url, got \(session.homeserverUrl)"
        )
        XCTAssertFalse(session.deviceId.isEmpty)

        try await client.logout()
    }
}

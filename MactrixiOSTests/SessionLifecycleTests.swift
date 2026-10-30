import Core
@testable import MactrixiOS
import XCTest

/// MATRIX-83: launch restore and the signed-out route.
///
/// A signed-in `MatrixClient` needs a homeserver, so these tests cover the
/// paths that end signed out. The dev-account smoke covers the signed-in path.
@MainActor
final class SessionLifecycleTests: XCTestCase {
    private struct TestError: Error {}

    @MainActor
    private final class Counter {
        var value = 0
    }

    func testPhaseIsRestoringBeforeTheRestoreRuns() {
        let lifecycle = SessionLifecycle(appState: AppState(), restore: { nil }, startSync: { _ in })

        XCTAssertEqual(lifecycle.phase, .restoring)
    }

    func testNoSavedSessionEndsSignedOut() async {
        let lifecycle = SessionLifecycle(appState: AppState(), restore: { nil }, startSync: { _ in })

        await lifecycle.restoreOnLaunch()

        XCTAssertEqual(lifecycle.phase, .signedOut)
        XCTAssertNil(lifecycle.appState.matrixClient)
    }

    func testFailedRestoreEndsSignedOut() async {
        let lifecycle = SessionLifecycle(appState: AppState(), restore: { throw TestError() }, startSync: { _ in })

        await lifecycle.restoreOnLaunch()

        XCTAssertEqual(lifecycle.phase, .signedOut)
    }

    func testRestoreRunsOncePerLaunch() async {
        let restoreCalls = Counter()
        let lifecycle = SessionLifecycle(
            appState: AppState(),
            restore: {
                restoreCalls.value += 1
                return nil
            },
            startSync: { _ in }
        )

        await lifecycle.restoreOnLaunch()
        await lifecycle.restoreOnLaunch()

        XCTAssertEqual(restoreCalls.value, 1)
    }

    func testAuthenticationFailureWithoutAClientStaysSignedOut() async {
        let lifecycle = SessionLifecycle(appState: AppState(), restore: { nil }, startSync: { _ in })
        await lifecycle.restoreOnLaunch()

        await lifecycle.handleAuthenticationFailure()

        XCTAssertEqual(lifecycle.phase, .signedOut)
    }

    func testRootViewModelOwnsTheLifecycleOfItsAppState() {
        let appState = AppState()
        let model = RootViewModel(appState: appState)

        XCTAssertTrue(model.session.appState === appState)
    }
}

import Core
@testable import MactrixiOS
import XCTest

/// MATRIX-82: the iOS shell reads its login state from Core.
@MainActor
final class RootViewModelTests: XCTestCase {
    func testFreshAppStateResolvesSignedOut() {
        let model = RootViewModel(appState: AppState())

        XCTAssertNil(model.appState.matrixClient)
        XCTAssertEqual(model.status, .signedOut)
        XCTAssertEqual(model.status.title, "Signed out")
    }

    func testUserIDResolvesSignedIn() {
        let status = SessionStatus(userID: "@patrick:davlin.io")

        XCTAssertEqual(status, .signedIn(userID: "@patrick:davlin.io"))
        XCTAssertEqual(status.title, "Signed in as @patrick:davlin.io")
    }

    func testMissingUserIDResolvesSignedOut() {
        XCTAssertEqual(SessionStatus(userID: nil), .signedOut)
    }
}
